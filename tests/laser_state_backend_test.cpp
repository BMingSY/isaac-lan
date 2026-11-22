#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/laser_state.cpp"
#include <iostream>
#include <map>
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned allocateEntry = 0x5eacf8, deleteEntry = 0x5eb08e, spriteOffset = 0x3c;
constexpr unsigned sampleStateOffset = 0x3ad, samplesOffset = 0x3cc;
constexpr std::array<unsigned, 6> valueOffsets{0x3b8, 0x3bc, 0x3c0, 0x3c4, 0x3c8, 0x430};
constexpr std::array<unsigned, 2> pathOffsets{0x3d0, 0x3dc};
#else
constexpr unsigned allocateEntry = 0x628740, deleteEntry = 0x70f939, spriteOffset = 0x48;
constexpr unsigned sampleStateOffset = 0x45d, samplesOffset = 0x47c;
constexpr std::array<unsigned, 6> valueOffsets{0x468, 0x46c, 0x470, 0x474, 0x478, 0x4e0};
constexpr std::array<unsigned, 2> pathOffsets{0x480, 0x48c};
#endif
struct lua_State {
    int top = 1;
    unsigned userdataBytes = 8;
    std::array<std::uintptr_t, 2> wrapper{};
    std::string input, output;
    double dx = 0, dy = 0;
    bool success = false;
};
namespace {
namespace state = isaac::engine::native_laser_state;
using Address = std::uintptr_t;
struct Vector {
    Address begin, end, capacity;
};
struct Block {
    std::vector<unsigned char> storage;
    unsigned size;
};
std::map<Address, Block> blocks;
unsigned allocations = 0, deletions = 0, failAt = 0;
bool replica = false;
std::string error;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* pointer) {
    return reinterpret_cast<Address>(pointer);
}
void* __cdecl allocate(std::size_t bytes) {
    ++allocations;
    if (allocations == failAt)
        return nullptr;
    Block block{std::vector<unsigned char>(bytes + 64, 0xa5), bytes};
    auto* result = block.storage.data() + 16;
    blocks.emplace(address(result), std::move(block));
    return result;
}
void __cdecl release(void* pointer, std::size_t bytes) {
    auto found = blocks.find(address(pointer));
    require(found != blocks.end() && found->second.size == bytes,
            "Native delete received an aligned interior pointer, wrong size or duplicate owner");
    const auto& memory = found->second.storage;
    require(std::all_of(memory.begin(), memory.begin() + 16, [](auto c) { return c == 0xa5; }) &&
                std::all_of(memory.end() - 48, memory.end(), [](auto c) { return c == 0xa5; }),
            "Laser storage overran its native allocation");
    blocks.erase(found);
    ++deletions;
}
void nativeDestroy(Vector& value) {
    if (!value.begin)
        return;
    auto raw = value.begin;
    auto bytes = value.capacity - value.begin;
    if (bytes >= 0x1000) {
        require(value.begin % 32 == 0, "Large game vector lost native alignment");
        raw = *reinterpret_cast<Address*>(value.begin - 4);
        require(value.begin - raw - 4 <= 31, "Game destructor rejected vector allocation header");
        bytes += 0x23;
    }
    release(reinterpret_cast<void*>(raw), bytes);
    value = {};
}
struct Laser {
    std::array<unsigned char, 0x600> data;
    Laser() {
        data.fill(0xa5);
        field<unsigned>(data.data(), 0x28) = 7;
        field<std::uint8_t>(data.data(), sampleStateOffset) = 255;
        field<unsigned>(data.data(), samplesOffset) = 0;
        for (auto offset : valueOffsets)
            field<float>(data.data(), offset) = 0;
        for (auto offset : pathOffsets)
            field<Vector>(data.data(), offset) = {};
    }
    void destroy() {
        for (auto offset : pathOffsets)
            nativeDestroy(field<Vector>(data.data(), offset));
    }
};
void u16(std::string& out, unsigned word) {
    out += static_cast<char>(word >> 8);
    out += static_cast<char>(word);
}
void u32(std::string& out, unsigned word) {
    u16(out, word >> 16);
    u16(out, word);
}
std::string packet(unsigned points, unsigned sample = 1) {
    std::string out(1, static_cast<char>(sample));
    for (float value : {1.f, 2.f, 3.f, 4.f, 5.f, 6.f})
        u32(out, std::bit_cast<unsigned>(value));
    u32(out, points);
    for (unsigned path = 0; path < 2; ++path) {
        u16(out, points);
        for (unsigned i = 0; i < points; ++i) {
            u32(out, std::bit_cast<unsigned>(float(i + path)));
            u32(out, std::bit_cast<unsigned>(-float(i + path)));
        }
    }
    return out;
}
lua_State invoke(Laser& laser, const std::string* input = nullptr, int arguments = 2, double x = 0,
                 double y = 0) {
    lua_State L;
    L.wrapper = {0x12345678, address(laser.data.data()) + spriteOffset};
    if (input) {
        L.top = arguments;
        L.input = *input;
    }
    L.dx = x;
    L.dy = y;
    error.clear();
    require(state::laserPath(&L) == 1, "Laser path return count changed");
    return L;
}
void reject(Laser& laser, const std::string& input, int arguments = 2, double x = 0, double y = 0) {
    const auto before = laser.data;
    const auto saved = blocks;
    const auto result = invoke(laser, &input, arguments, x, y);
    require(!result.success && laser.data == before && blocks.size() == saved.size(),
            "Invalid laser snapshot modified entity or changed native owners");
    for (const auto& [key, block] : saved)
        require(blocks.contains(key) && blocks.at(key).storage == block.storage,
                "Rejected laser snapshot modified an existing native path");
}
void configure() {
    state::lua.getTop = [](lua_State* L) { return L->top; };
    state::lua.toUserdata = [](lua_State* L, int) -> void* { return L->wrapper.data(); };
    state::lua.rawLength = [](lua_State* L, int) -> std::size_t { return L->userdataBytes; };
    state::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    state::lua.checkNumber = [](lua_State* L, int index) { return index == 3 ? L->dx : L->dy; };
    state::lua.pushLString = [](lua_State* L, const char* value, std::size_t size) -> const char* {
        L->output.assign(value, size);
        return L->output.c_str();
    };
    state::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
}
void jump(unsigned char* image, unsigned rva, void* target) {
    auto* entry = image + rva;
    entry[0] = 0xe9;
    const auto relative = address(target) - address(entry + 5);
    std::memcpy(entry + 1, &relative, 4);
    FlushInstructionCache(GetCurrentProcess(), entry, 5);
}
unsigned __attribute__((stdcall)) allocatorProbe(unsigned size) {
    auto* pointer = state::engine<state::Allocate>(allocateEntry)(size);
    state::engine<state::Delete>(deleteEntry)(pointer, size);
    return 123;
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& message) {
    error = message;
}
} // namespace isaac::runtime
int main() {
    try {
        configure();
        auto* image = static_cast<unsigned char*>(VirtualAlloc(
            nullptr, privateGameImageBytes, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate laser fixture");
        state::image = address(image);
        jump(image, allocateEntry, reinterpret_cast<void*>(allocate));
        jump(image, deleteEntry, reinterpret_cast<void*>(release));
        const auto abi =
            native_fixture::call(reinterpret_cast<void*>(allocatorProbe), nullptr, {24});
        require(abi.balanced && abi.preserved && abi.eax == 123 && blocks.empty(),
                "Native allocator caller violated x86 ABI");
        Laser laser;
        const auto pristine = laser.data;
        const auto fresh = invoke(laser).output;
        require(fresh.size() == 33 && static_cast<unsigned char>(fresh[0]) == 255 &&
                    fresh.substr(1) == std::string(32, '\0') && laser.data == pristine,
                "Fresh laser lost native tri-state or empty wire shape");
        const auto small = packet(2);
        reject(laser, small);
        replica = true;
        for (unsigned i = 0; i < small.size(); ++i)
            reject(laser, small.substr(0, i));
        reject(laser, small + 'x');
        auto invalid = small;
        invalid[0] = 2;
        reject(laser, invalid);
        invalid = small;
        invalid.replace(1, 4, std::string("\x7f\x80\0\0", 4));
        reject(laser, invalid);
        invalid = small;
        invalid.replace(25, 4, std::string("\0\0\x08\x01", 4));
        reject(laser, invalid);
        invalid = small;
        invalid.replace(29, 2, std::string("\x08\x01", 2));
        reject(laser, invalid);
        invalid = small;
        invalid.replace(31, 4, std::string("\x7f\xc0\0\0", 4));
        reject(laser, invalid);
        reject(laser, small, 3);
        reject(laser, small, 4, INFINITY, 0);
        invalid = small;
        invalid.replace(1, 4, std::string("\x7f\x7f\xff\xff", 4));
        reject(laser, invalid, 4, std::numeric_limits<float>::max(), 0);
        require(invoke(laser, &small).success && invoke(laser).output == small,
                "Laser snapshot changed wire order or version fields");
        auto expected = pristine;
        for (auto offset : pathOffsets)
            std::memcpy(expected.data() + offset, laser.data.data() + offset, 12);
        for (auto offset : valueOffsets)
            std::memcpy(expected.data() + offset, laser.data.data() + offset, 4);
        expected[sampleStateOffset] = 1;
        field<unsigned>(expected.data(), samplesOffset) = 2;
        require(laser.data == expected, "Laser restore touched unrelated or owned native state");
        const auto owners = laser.data;
        const auto allocated = allocations;
        require(invoke(laser, &small).success && laser.data == owners && allocations == allocated,
                "Repeated laser snapshot reallocated native paths");
        require(invoke(laser, &small, 4, 10, -20).success, "Valid render translation rejected");
        for (unsigned i = 0; i < 6; ++i)
            require(field<float>(laser.data.data(), valueOffsets[i]) ==
                        float(i + 1) + (i < 4 ? (i % 2 ? -20 : 10) : 0),
                    "Render translation changed shape/scale or missed origin/endpoint");
        auto first = field<Vector>(laser.data.data(), pathOffsets[0]);
        require(field<float>(reinterpret_cast<void*>(first.begin), 0) == 10 &&
                    field<float>(reinterpret_cast<void*>(first.begin), 4) == -20,
                "Path coordinates missed render translation");
        const auto translated = invoke(laser).output;
        require(invoke(laser, &small, 4, 10, -20).success && invoke(laser).output == translated,
                "Repeated render offsets accumulated");
        require(invoke(laser, &small).success, "Restore base snapshot");
        failAt = allocations + 2;
        const auto big = packet(2048);
        reject(laser, big);
        failAt = 0;
        auto& second = field<Vector>(laser.data.data(), pathOffsets[1]);
        const auto savedEnd = second.end;
        second.end = second.capacity + 8;
        reject(laser, big);
        second.end = savedEnd;
        laser.destroy();
        require(blocks.empty(), "Small paths were not compatible with game destructor");
        for (unsigned count : {255u, 256u, 2048u}) {
            const auto next = packet(count, 255);
            require(invoke(laser, &next).success && invoke(laser).output == next,
                    "Native path allocation boundary changed snapshot bytes");
            for (auto offset : pathOffsets) {
                const auto vector = field<Vector>(laser.data.data(), offset);
                require(vector.end - vector.begin == count * 8 &&
                            vector.capacity - vector.begin >= count * 8,
                        "Native vector size/capacity invalid after growth");
            }
            const auto before = allocations;
            require(invoke(laser, &next).success && allocations == before,
                    "Repeated large path recreated storage");
            laser.destroy();
            require(blocks.empty(), "Large path header incompatible with native deletion");
        }
        require(invoke(laser, &big).success, "Create aligned path owner");
        auto& large = field<Vector>(laser.data.data(), pathOffsets[0]);
        auto* header = reinterpret_cast<Address*>(large.begin - 4);
        const auto originalHeader = *header;
        *header = large.begin;
        reject(laser, small);
        require(invoke(laser).output.empty(), "Capture accepted corrupt native allocation header");
        *header = originalHeader;
        require(invoke(laser, &fresh).success && invoke(laser).output == fresh,
                "Empty snapshot did not retain reusable native buffers");
        laser.destroy();
        for (unsigned size : {0u, 4u, 12u, 0x11cu}) {
            lua_State L;
            L.wrapper[1] = address(laser.data.data()) + spriteOffset;
            L.userdataBytes = size;
            require(state::laserPath(&L) == 1 && !L.success && L.output.empty(),
                    "Owning or malformed Sprite accepted as laser");
        }
        field<unsigned>(laser.data.data(), 0x28) = 2;
        require(invoke(laser).output.empty(), "Non-laser entity accepted");
        lua_State null;
        null.wrapper[1] = spriteOffset;
        require(state::laserPath(&null) == 1 && null.output.empty(), "Null laser was dereferenced");
        require(blocks.empty(), "Laser fixture leaked game storage");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout << "Laser wire bytes, translation, atomic allocation failure and native aligned "
                     "ownership passed\n";
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}

#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/sprite_state.cpp"
#include <map>
#include <variant>
#include <iostream>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned layerStride = 0x9c, layerFlagsOffset = 0x88, cropOffset = 0x8c;
constexpr unsigned nativeBlendCount = 4;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
constexpr unsigned layerStride = 0xa0, layerFlagsOffset = 0x8c, cropOffset = 0x90;
constexpr unsigned nativeBlendCount = 5;
#endif
struct lua_State {
    int top = 1, tables = 0;
    std::size_t userdataBytes = 8;
    std::array<std::uintptr_t, 2> wrapper{};
    bool validWrapper = true, success = false;
    std::string input, output;
    long long integer = 0;
    std::variant<std::monostate, long long, std::string> value;
    std::pair<unsigned, std::string> current;
    std::vector<std::pair<unsigned, std::string>> changes;
};
namespace {
namespace sprite = isaac::engine::native_sprite;
namespace lan = isaac::lan;
using Address = std::uintptr_t;
bool replica = false;
unsigned resets = 0, releasedArrays = 0;
void* resetReceiver = nullptr;
std::string lastError;
std::map<Address, unsigned> frameArrays;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* pointer) {
    return reinterpret_cast<Address>(pointer);
}
std::string hexBytes(const std::string& text) {
    std::string result;
    for (unsigned i = 0; i < text.size(); i += 2)
        result += static_cast<char>(std::stoul(text.substr(i, 2), nullptr, 16));
    return result;
}
void __attribute__((fastcall)) nativeReset(void* state, void*, void* data) {
    require(!data, "Sprite detach allocated an unrelated native animation");
    ++resets;
    resetReceiver = state;
    for (unsigned offset : {8, 12}) {
        const auto frames = field<Address>(state, offset);
        if (frames) {
            require(frameArrays.erase(frames) == 1,
                    "Animation reset released unowned frame storage");
            ++releasedArrays;
            field<Address>(state, offset) = 0;
        }
    }
    field<Address>(state, 4) = 0;
    field<float>(state, 0x10) = -1;
    field<bool>(state, 0x14) = false;
    field<unsigned>(state, 0x18) = field<unsigned>(state, 0x1c) = 0;
}
struct NativeSprite {
    std::array<unsigned char, 0x114> object;
    std::array<std::array<unsigned char, layerStride>, 3> layers;
    std::array<unsigned, 3> ids{7, 2, 11};
    std::array<std::array<unsigned char, 0x13c>, 2> animations{};
    std::array<std::array<std::array<unsigned, 4>, 3>, 2> animationLayers{}, nullLayers{};
    std::array<std::array<int, 3>, 2> cursors{}, nullCursors{};
    std::string heapPath = "a/long/native/texture/path.png";
    NativeSprite() {
        object.fill(0xa5);
        field<Address>(object.data(), 0x34) = field<Address>(object.data(), 0x54) = 0;
        field<Address>(object.data(), 0x30) = field<Address>(object.data(), 0x50) =
            address(object.data());
        field<Address>(object.data(), 0x7c) = address(layers.data());
        field<unsigned>(object.data(), 0x80) = 0;
        field<int>(object.data(), 0x10c) = -1;
        field<float>(object.data(), 0x104) = 1;
        field<unsigned>(object.data(), 0x110) = 0xaabbccdd;
        field<bool>(object.data(), 0x70) = true;
        for (unsigned offset = 0xa8; offset < 0x100; offset += 4)
            field<unsigned>(object.data(), offset) = 0;
        for (unsigned i = 0; i < layers.size(); ++i) {
            auto* layer = layers[i].data();
            layers[i].fill(0xa5);
            field<Address>(layer, 0) = address(&ids[i]);
            field<Address>(layer, 4) = address(object.data());
            setPath(i, "sheet");
            field<bool>(layer, 0x32) = true;
            field<bool>(layer, 0x33) = false;
            field<bool>(layer, 0x74) = true;
            for (unsigned offset = 0x34; offset <= 0x70; offset += 4)
                field<float>(layer, offset) = 1;
            field<float>(layer, cropOffset) = field<float>(layer, cropOffset + 4) = 1;
            for (unsigned j = 0; j < nativeBlendCount; ++j)
                field<unsigned>(layer, 0x78 + j * 4) = j + 1;
            field<unsigned>(layer, layerFlagsOffset) = 0x80000400;
        }
    }
    void setPath(unsigned slot, const std::string& text) {
        auto* value = layers[slot].data() + 8;
        if (text.size() <= 15) {
            std::memset(value, 0, 16);
            std::memcpy(value, text.data(), text.size());
            field<unsigned>(value, 0x14) = 15;
        } else {
            require(text == heapPath, "Fixture heap string must remain alive");
            field<Address>(value, 0) = address(heapPath.c_str());
            field<unsigned>(value, 0x14) = heapPath.size();
        }
        field<unsigned>(value, 0x10) = text.size();
    }
    void animate(unsigned slot, std::array<unsigned, 3> order, std::array<unsigned, 3> nullOrder) {
        auto* data = animations[slot].data();
        auto* state = object.data() + (slot ? 0x50 : 0x30);
        field<Address>(state, 4) = address(data);
        field<Address>(state, 8) = address(cursors[slot].data());
        field<Address>(state, 12) = address(nullCursors[slot].data());
        frameArrays[address(cursors[slot].data())] = 3;
        frameArrays[address(nullCursors[slot].data())] = 3;
        field<float>(state, 0x10) = 2.5f;
        field<bool>(state, 0x14) = true;
        field<unsigned>(state, 0x18) = 0x10;
        field<unsigned>(state, 0x1c) = 0x20;
        field<Address>(data, 0x18) = address(animationLayers[slot].data());
        field<unsigned>(data, 0x1c) = 3;
        field<Address>(data, 0x20) = address(nullLayers[slot].data());
        field<unsigned>(data, 0x24) = 3;
        field<unsigned>(data, 0x28) = 0xfefefefe; // Never the native null-layer count.
        field<unsigned>(data, 0x30) = 42;
        for (unsigned i = 0; i < 64; ++i)
            field<int>(data, 0x38 + 4 * i) = -1;
        for (unsigned i = 0; i < 3; ++i) {
            animationLayers[slot][i] = {order[i], 0, 8, 1};
            nullLayers[slot][i] = {nullOrder[i], 0, 0, 8};
            field<unsigned>(data, 0x38 + order[i] * 4) = i;
            cursors[slot][i] = i + 1;
            nullCursors[slot][i] = i + 4;
        }
    }
};
struct Snapshot {
    std::array<unsigned char, 0x114> object;
    decltype(NativeSprite::layers) layers;
    decltype(NativeSprite::animations) animations;
    decltype(NativeSprite::cursors) cursors, nullCursors;
    explicit Snapshot(const NativeSprite& sprite)
        : object(sprite.object), layers(sprite.layers), animations(sprite.animations),
          cursors(sprite.cursors), nullCursors(sprite.nullCursors) {}
    bool matches(const NativeSprite& sprite) const {
        return object == sprite.object && layers == sprite.layers &&
               animations == sprite.animations && cursors == sprite.cursors &&
               nullCursors == sprite.nullCursors;
    }
};
lua_State capture(NativeSprite& object) {
    lua_State L;
    L.wrapper = {0x87654321, address(object.object.data())};
    require(sprite::state(&L) == 1, "Sprite capture return count changed");
    return L;
}
lua_State applyPose(NativeSprite& object, const std::string& packet) {
    lua_State L;
    L.top = 2;
    L.input = packet;
    L.wrapper = {0x87654321, address(object.object.data())};
    require(sprite::state(&L) == 1, "Sprite restore return count changed");
    return L;
}
void configureLua() {
    sprite::lua.getTop = [](lua_State* L) { return L->top; };
    sprite::lua.toUserdata = [](lua_State* L, int) -> void* {
        return L->validWrapper ? L->wrapper.data() : nullptr;
    };
    sprite::lua.rawLength = [](lua_State* L, int) { return L->userdataBytes; };
    sprite::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    sprite::lua.pushLString = [](lua_State* L, const char* value, std::size_t size) -> const char* {
        if (!L->tables) {
            L->output.assign(value, size);
            return L->output.c_str();
        }
        L->value = std::string(value, size);
        return std::get<std::string>(L->value).c_str();
    };
    sprite::lua.pushInteger = [](lua_State* L, long long value) {
        L->integer = value;
        L->value = value;
    };
    sprite::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
    sprite::lua.createTable = [](lua_State* L, int, int) {
        ++L->tables;
        L->current = {};
    };
    sprite::lua.rawSetI = [](lua_State* L, int, long long index) {
        if (auto number = std::get_if<long long>(&L->value)) {
            require(index == 1, "Changed texture ID field moved");
            L->current.first = *number;
        } else if (auto text = std::get_if<std::string>(&L->value)) {
            require(index == 2, "Changed texture path field moved");
            L->current.second = *text;
        } else {
            require(L->tables == 2 && index == static_cast<long long>(L->changes.size() + 1),
                    "Changed texture list is not contiguous");
            L->changes.push_back(L->current);
            --L->tables;
        }
        L->value = std::monostate{};
    };
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& reason) {
    lastError = reason;
}
} // namespace isaac::runtime
int main() {
    try {
        configureLua();
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, 0x10000, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate native Sprite reset fixture");
        auto* entry = image + backend::entry::animationStateReset;
        entry[0] = 0xe9;
        const auto relative = address(reinterpret_cast<void*>(nativeReset)) - address(entry + 5);
        std::memcpy(entry + 1, &relative, 4);
        FlushInstructionCache(GetCurrentProcess(), image, 0x10000);
        sprite::image = address(image);
        NativeSprite empty;
        const Snapshot emptyBefore(empty);
        const auto emptyPacket = capture(empty).output;
        const auto emptyGolden =
            hexBytes("020000ffffffff") + std::string(88, '\0') + hexBytes("3f800000aabbccdd010000");
        require(emptyPacket == emptyGolden && emptyBefore.matches(empty),
                "Empty Sprite encoding changed or capture modified its resources");
        auto wrapper = capture(empty);
        wrapper.userdataBytes = 0x11c;
        wrapper.output.clear();
        sprite::state(&wrapper);
        require(wrapper.output == emptyGolden, "Owning Sprite wrapper cannot be captured");
        for (auto size : {0u, 4u, 12u, 0x118u}) {
            wrapper.userdataBytes = size;
            wrapper.output.clear();
            sprite::state(&wrapper);
            require(wrapper.output.empty() && !wrapper.success,
                    "Invalid Sprite userdata was dereferenced");
        }

        NativeSprite one;
        field<unsigned>(one.object.data(), 0x80) = 1;
        field<int>(one.object.data(), 0x10c) = 7;
        auto golden = hexBytes("02000000000007") + std::string(88, '\0') +
                      hexBytes("3f800000aabbccdd010001000700057368656574010001");
        for (unsigned i = 0; i < 18; ++i)
            golden += hexBytes("3f800000");
        golden += hexBytes("00000001000000020000000300000004");
        golden += hexBytes(nativeBlendCount == 4 ? "00000000" : "00000005");
        golden += hexBytes("80000400");
        const Snapshot oneBefore(one);
        const auto packet = capture(one).output;
        require(packet == golden && oneBefore.matches(one),
                "Layer wire format read a pointer, wrong crop position or wrong blend width");
        require(!applyPose(one, packet).success && oneBefore.matches(one),
                "Authority accepted a Sprite write");
        replica = true;
        require(applyPose(one, packet).success && oneBefore.matches(one),
                "Repeated Sprite pose changed resources, filters or self references");
        for (unsigned length = 0; length < packet.size(); ++length)
            require(!applyPose(one, packet.substr(0, length)).success && oneBefore.matches(one),
                    "Truncated pose partially changed a native Sprite");
        for (unsigned invalid : {0u, 1u, 2u, 3u, 4u}) {
            auto bad = packet;
            if (invalid == 0)
                bad += 'x';
            else if (invalid == 1)
                bad[115] = 2; // First layer's flip-X flag.
            else if (invalid == 2)
                bad.replace(bad.size() - 8, 4, hexBytes("00000021"));
            else if (invalid == 3)
                bad.replace(7, 4, hexBytes("7fc00000"));
            else {
                bad[105] = 2;
                bad += packet.substr(106);
            }
            require(!applyPose(one, bad).success && oneBefore.matches(one),
                    "Invalid visual values or duplicate IDs partially changed a Sprite");
        }
#ifdef ISAAC_LAN_TEST_J835
        auto nonzeroReserved = packet;
        nonzeroReserved.replace(nonzeroReserved.size() - 8, 4, hexBytes("00000001"));
        require(!applyPose(one, nonzeroReserved).success && oneBefore.matches(one),
                "J835 wrote the absent blend word over flags or native resource pointers");
#endif
        one.setPath(0, one.heapPath);
        const auto heapPacket = capture(one).output;
        one.setPath(0, "local");
        const auto localResources = one.layers;
        const auto changed = applyPose(one, heapPacket);
        require(changed.changes ==
                        std::vector<std::pair<unsigned, std::string>>{{7, one.heapPath}} &&
                    one.layers == localResources,
                "Sprite synchronization overwrote an owned texture string instead of returning a "
                "request");
        field<unsigned>(one.layers[0].data() + 8, 0x10) = 16;
        const auto malformed = capture(one);
        require(malformed.output.empty() && !malformed.success,
                "Malformed native string escaped capture");
        one.setPath(0, "local");

        NativeSprite host, guest;
        field<unsigned>(host.object.data(), 0x80) = field<unsigned>(guest.object.data(), 0x80) = 3;
        field<int>(host.object.data(), 0x10c) = 11;
        host.animate(0, {7, 2, 11}, {14, 8, 6});
        host.animate(1, {2, 7, 11}, {8, 14, 6});
        guest.ids = {2, 7, 15};
        guest.animate(0, {2, 7, 15}, {8, 14, 9});
        guest.animate(1, {7, 2, 15}, {14, 8, 9});
        const auto hostPacket = capture(host).output;
        const auto guestResources = guest.layers;
        const auto guestAnimationData = guest.animations;
        const auto beforePointers = guest.object;
        require(
            applyPose(guest, hostPacket).success && guest.cursors[0] == std::array{2, 1, 3} &&
                guest.cursors[1] == std::array{2, 1, 3} &&
                guest.nullCursors[0] == std::array{5, 4, -1} &&
                guest.nullCursors[1] == std::array{5, 4, -1} &&
                field<int>(guest.object.data(), 0x10c) == -1,
            "Animation cursors were matched by array order or missing attachment state survived");
        require(guest.layers == guestResources && guest.animations == guestAnimationData,
                "Applying reordered animation altered native definitions or texture resources");
        for (unsigned offset : {0x30, 0x34, 0x38, 0x3c, 0x50, 0x54, 0x58, 0x5c, 0x7c})
            require(std::memcmp(beforePointers.data() + offset, guest.object.data() + offset, 4) ==
                        0,
                    "Sprite synchronization replaced a native animation or frame-array owner");
        auto length = capture(guest);
        length.integer = 0;
        sprite::animationLength(&length);
        require(length.integer == 42, "Animation length read the wrong native field");
        host.cursors[0][0] = 100;
        host.nullCursors[0][0] = 100;
        const auto invalidCursorPacket = capture(host).output;
        require(applyPose(guest, invalidCursorPacket).success && guest.cursors[0][1] == 1 &&
                    guest.nullCursors[0][1] == -1,
                "Out-of-range frame cursor reached a local animation array");
        field<Address>(guest.object.data(), 0x5c) = 0;
        const Snapshot missingFrames(guest);
        require(!applyPose(guest, hostPacket).success && missingFrames.matches(guest),
                "Missing overlay arrays were discovered after main-animation writes");
        field<Address>(guest.object.data(), 0x5c) = address(guest.nullCursors[1].data());
        const auto beforeReset = resets;
        require(applyPose(guest, emptyPacket).success && resets == beforeReset + 2 &&
                    releasedArrays == 4 && field<Address>(guest.object.data(), 0x34) == 0 &&
                    field<Address>(guest.object.data(), 0x54) == 0,
                "Absent animation did not use the native destructor/reset boundary");
        require(applyPose(guest, emptyPacket).success && resets == beforeReset + 2,
                "Repeated empty animation released its frame arrays twice");
        const auto abi = native_fixture::call(entry, guest.object.data() + 0x30, {0});
        require(abi.balanced && abi.preserved && resetReceiver == guest.object.data() + 0x30,
                "Animation Reset violated its thiscall ABI");
        field<Address>(host.object.data(), 0x38) = 0;
        require(capture(host).output.empty(), "Missing host frame arrays were read during capture");
        frameArrays.clear();
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout << "Sprite native layouts, atomic validation, ownership and fixed bytes passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

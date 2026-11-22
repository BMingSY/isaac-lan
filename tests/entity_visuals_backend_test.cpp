#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/entity_visuals.cpp"
#include <iostream>
#include <limits>
#include <vector>
#ifdef ISAAC_LAN_TEST_REPENTANCE
constexpr unsigned spriteOffset = 0x3c, extraOffset = 0xe18, layerStride = 0x9c;
constexpr unsigned bodyVtable = 0x746348, tetherVtable = 0x73fffc;
constexpr unsigned prepareEntry = 0x13c430, renderEntry = 0x26810;
#else
constexpr unsigned spriteOffset = 0x48, extraOffset = 0xee0, layerStride = 0xa0;
constexpr unsigned bodyVtable = 0x787bf4, tetherVtable = 0x780ffc;
constexpr unsigned prepareEntry = 0x155ea0, renderEntry = 0x394b0;
#endif
struct lua_State {
    int top = 1;
    std::array<std::array<std::uintptr_t, 2>, 3> wrappers{};
    std::array<std::size_t, 3> sizes{8, 8, 8};
    std::array<bool, 3> missing{};
    std::string input, output;
    std::vector<std::array<std::uintptr_t, 2>> borrowed;
    unsigned metatables = 0, elements = 0, tableSize = 0;
    bool success = false;
};
namespace {
namespace visuals = isaac::engine::native_visuals;
using Address = std::uintptr_t;
bool replica = false, failRender = false;
unsigned renders = 0, prepares = 0;
void* prepared = nullptr;
std::string lastError;
std::array<unsigned char, 0x114> expectedSprite;
std::vector<std::array<float, 3>> rendered;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* object) {
    return reinterpret_cast<Address>(object);
}
std::string hexBytes(const std::string& text) {
    std::string result;
    for (unsigned i = 0; i < text.size(); i += 2)
        result += static_cast<char>(std::stoul(text.substr(i, 2), nullptr, 16));
    return result;
}
void patch(unsigned char* image, unsigned rva, void* target) {
    image[rva] = 0xe9;
    auto delta = address(target) - address(image + rva + 5);
    std::memcpy(image + rva + 1, &delta, 4);
}
void __attribute__((fastcall)) nativePrepare(void* entity, void*) {
    prepared = entity;
    ++prepares;
}
void __attribute__((fastcall)) nativeRender(void* familiar, void*, const float* offset, int part) {
    require(offset && offset[0] == 0 && offset[1] == 0 && part == 0,
            "Tether render changed its native arguments");
    const auto data = reinterpret_cast<void*>(field<Address>(familiar, extraOffset));
    require(data && field<Address>(data, 0) == visuals::image + tetherVtable,
            "Tether render did not use the version's native type");
    require(std::memcmp(static_cast<unsigned char*>(data) + 0x18, expectedSprite.data(), 0x114) ==
                0,
            "Tether render modified or reloaded the borrowed Sprite");
    const auto count = field<unsigned>(data, 0x14);
    const auto capacity = field<unsigned>(data, 0xc);
    require(count > 1 && count <= 256 && capacity == 256,
            "Tether stack view has an invalid native deque");
    const auto map = reinterpret_cast<Address*>(field<Address>(data, 8));
    rendered.clear();
    for (unsigned i = 0; i < count; ++i) {
        const auto point = reinterpret_cast<float*>(map[(field<unsigned>(data, 0x10) + i) & 255]);
        rendered.push_back({point[0], point[1], point[2]});
    }
    ++renders;
    if (failRender)
        throw std::runtime_error("Fixture native render exception");
}
void configureLua() {
    visuals::lua.getTop = [](lua_State* L) { return L->top; };
    visuals::lua.toUserdata = [](lua_State* L, int n) -> void* {
        return L->missing.at(n) ? nullptr : L->wrappers.at(n).data();
    };
    visuals::lua.rawLength = [](lua_State* L, int n) { return L->sizes.at(n); };
    visuals::lua.checkString = [](lua_State* L, int n, std::size_t* size) {
        require(n == L->top, "Native visual payload used the wrong Lua argument");
        *size = L->input.size();
        return L->input.c_str();
    };
    visuals::lua.pushLString = [](lua_State* L, const char* bytes, std::size_t size) {
        L->output.assign(bytes, size);
        return L->output.c_str();
    };
    visuals::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
    visuals::lua.createTable = [](lua_State* L, int size, int records) {
        require(records == 0, "Body sprites must use an ordered array");
        L->tableSize = size;
    };
    visuals::lua.newUserdata = [](lua_State* L, std::size_t size) -> void* {
        require(size == 8, "Visual capture created an owning Sprite");
        return L->borrowed.emplace_back().data();
    };
    visuals::lua.getMetatable = [](lua_State*, int n) {
        require(n == 1, "Sprite metatable was not borrowed from its source");
        return 1;
    };
    visuals::lua.setMetatable = [](lua_State* L, int n) {
        require(n == -2, "Metatable applied to wrong value");
        ++L->metatables;
        return 1;
    };
    visuals::lua.rawSetI = [](lua_State* L, int n, long long index) {
        require(n == -2 && index == ++L->elements, "Body sprites lost their native order");
    };
}
lua_State argument(void* familiar) {
    lua_State L;
    L.wrappers[1] = {0x12345678, address(familiar) + spriteOffset};
    return L;
}
lua_State bodyCapture(void* familiar) {
    auto L = argument(familiar);
    visuals::familiarBody(&L);
    return L;
}
lua_State restoreBody(void* familiar, const std::string& bytes) {
    auto L = argument(familiar);
    L.top = 2;
    L.input = bytes;
    visuals::familiarBody(&L);
    return L;
}
lua_State tetherCapture(void* familiar) {
    auto L = argument(familiar);
    visuals::familiarTether(&L);
    return L;
}
lua_State drawTether(void* familiar, const std::string& bytes, std::size_t wrapperSize = 0x11c) {
    auto L = argument(familiar);
    L.top = 3;
    L.wrappers[2] = {0x12345678, address(expectedSprite.data())};
    L.sizes[2] = wrapperSize;
    L.input = bytes;
    visuals::renderTether(&L);
    return L;
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
        constexpr unsigned imageSize = 0x800000;
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate native visual fixture");
        patch(image, prepareEntry, reinterpret_cast<void*>(nativePrepare));
        patch(image, renderEntry, reinterpret_cast<void*>(nativeRender));
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        visuals::image = address(image);
        std::array<unsigned char, 0xf00> familiar{};
        field<unsigned>(familiar.data(), 0x28) = 3;
        require(bodyCapture(familiar.data()).borrowed.empty() &&
                    tetherCapture(familiar.data()).borrowed.empty(),
                "Absent familiar component returned native resources");

        std::array<unsigned char, 0x580> body{};
        std::array<std::array<unsigned char, layerStride>, 4> layers{};
        std::array<unsigned, 4> ids{11, 23, 0, 63};
        field<Address>(body.data(), 0) = address(image) + bodyVtable;
        field<Address>(familiar.data(), extraOffset) = address(body.data());
        for (unsigned i = 0; i < 4; ++i) {
            auto* sprite = body.data() + 4 + (i + 1) * 0x114;
            field<Address>(sprite, 0x7c) = address(layers[i].data());
            field<unsigned>(sprite, 0x80) = 1;
            field<Address>(layers[i].data(), 0) = address(&ids[i]);
            field<int>(body.data(), 0x568 + i * 4) = -1;
        }
        const auto initialBody = body;
        const auto captured = bodyCapture(familiar.data());
        require(captured.output == std::string(16, '\xff') && captured.borrowed.size() == 5 &&
                    captured.metatables == 5 && captured.elements == 5 && captured.tableSize == 5,
                "Body snapshot changed the fixed layer bytes or Sprite count");
        for (unsigned i = 0; i < 5; ++i)
            require(captured.borrowed[i] ==
                        std::array<Address, 2>{0x12345678, address(body.data()) + 4 + i * 0x114},
                    "Body Sprite did not retain its borrowed native identity");
        const auto bodyBytes = hexBytes("0000000b00000017ffffffff0000003f");
        require(!restoreBody(familiar.data(), bodyBytes).success && body == initialBody,
                "Authority restored familiar body layers");
        replica = true;
        require(restoreBody(familiar.data(), bodyBytes).success, "Body layers did not restore");
        auto restoredBody = initialBody;
        const std::array<int, 4> expected{11, 23, -1, 63};
        std::memcpy(restoredBody.data() + 0x568, expected.data(), 16);
        require(body == restoredBody && bodyCapture(familiar.data()).output == bodyBytes,
                "Body restore changed Sprite resources or layer bytes");
        require(restoreBody(familiar.data(), bodyBytes).success && body == restoredBody,
                "Repeated body restore accumulated state");
        for (unsigned size = 0; size < bodyBytes.size(); ++size)
            require(!restoreBody(familiar.data(), bodyBytes.substr(0, size)).success &&
                        body == restoredBody,
                    "Truncated body packet caused a partial write");
        for (auto bytes : {hexBytes("fffffffffffffffffffffffffffffffe"),
                           hexBytes("ffffffffffffffffffffffff00000040"), bodyBytes + "x"})
            require(!restoreBody(familiar.data(), bytes).success && body == restoredBody,
                    "Invalid final body layer changed earlier layers");
        field<Address>(body.data(), 4 + 4 * 0x114 + 0x7c) = 0;
        const auto missingBody = body;
        require(!restoreBody(familiar.data(), bodyBytes).success && body == missingBody,
                "Missing body Sprite layers caused a partial restore");
        body = restoredBody;
        require(restoreBody(familiar.data(), captured.output).success && body == initialBody,
                "Empty body layer snapshot did not clear all four layers");

        std::array<unsigned char, 0x158> tether{};
        std::array<std::array<float, 3>, 3> points{{{20, 10, -8}, {40, 12, -12}, {60, 10, -6}}};
        std::array<Address, 256> pointMap{};
        for (unsigned i = 0; i < 3; ++i)
            pointMap[(255 + i) & 255] = address(points[i].data());
        for (unsigned i = 0; i < expectedSprite.size(); ++i)
            expectedSprite[i] = static_cast<unsigned char>(i * 7);
        field<Address>(tether.data(), 0) = address(image) + tetherVtable;
        field<Address>(tether.data(), 8) = address(pointMap.data());
        field<unsigned>(tether.data(), 0xc) = 256;
        field<unsigned>(tether.data(), 0x10) = 255;
        field<unsigned>(tether.data(), 0x14) = 3;
        std::memcpy(tether.data() + 0x18, expectedSprite.data(), expectedSprite.size());
        field<Address>(familiar.data(), extraOffset) = address(tether.data());
        const auto nativeTether = tether;
        const auto nativeFamiliar = familiar;
        const auto ropeBytes = hexBytes(
            "000341a0000041200000c10000004220000041400000c14000004270000041200000c0c00000");
        const auto rope = tetherCapture(familiar.data());
        require(rope.output == ropeBytes && rope.metatables == 1 && rope.borrowed.size() == 1 &&
                    rope.borrowed[0] ==
                        std::array<Address, 2>{0x12345678, address(tether.data()) + 0x18},
                "Wrapped native tether capture changed point order, bytes or Sprite ownership");
        require(bodyCapture(familiar.data()).borrowed.empty(), "Tether passed the body type check");
        require(drawTether(familiar.data(), ropeBytes).success && renders == 1 &&
                    rendered == std::vector<std::array<float, 3>>(points.begin(), points.end()) &&
                    familiar == nativeFamiliar && tether == nativeTether,
                "Native tether draw changed its geometry or retained a borrowed component");
        require(drawTether(familiar.data(), ropeBytes, 8).success && renders == 2 &&
                    familiar == nativeFamiliar && tether == nativeTether,
                "Repeated tether draw modified native resources");
        failRender = true;
        require(!drawTether(familiar.data(), ropeBytes).success && familiar == nativeFamiliar &&
                    tether == nativeTether && lastError == "Fixture native render exception",
                "Native render exception leaked the temporary component");
        failRender = false;
        const auto completed = renders;
        for (unsigned size = 0; size < ropeBytes.size(); ++size)
            require(!drawTether(familiar.data(), ropeBytes.substr(0, size)).success &&
                        renders == completed && familiar == nativeFamiliar,
                    "Truncated tether snapshot reached native render");
        for (auto bytes :
             {ropeBytes + "x", hexBytes("0101"), hexBytes("000141a00000412000007f800000")})
            require(!drawTether(familiar.data(), bytes).success && renders == completed,
                    "Invalid tether count, trailing data or coordinate reached render");
        require(drawTether(familiar.data(), hexBytes("0000")).success &&
                    drawTether(familiar.data(), hexBytes("000141a0000041200000c1000000")).success &&
                    renders == completed,
                "Empty or single-point rope called native render");
        require(!drawTether(familiar.data(), ropeBytes, 4).success,
                "Invalid rope wrapper accepted");
        auto nullSprite = argument(familiar.data());
        nullSprite.top = 3;
        nullSprite.input = ropeBytes;
        visuals::renderTether(&nullSprite);
        require(!nullSprite.success && renders == completed, "Null rope Sprite reached memcpy");
        replica = false;
        require(!drawTether(familiar.data(), ropeBytes).success && renders == completed,
                "Authority used replica tether rendering");
        for (unsigned offset : {8u, 0xcu}) {
            field<unsigned>(tether.data(), offset) = 0;
            require(tetherCapture(familiar.data()).output.empty(), "Null tether map was captured");
            tether = nativeTether;
        }
        pointMap[0] = 0;
        require(tetherCapture(familiar.data()).output.empty(), "Null tether point was read");
        pointMap[0] = address(points[1].data());
        points[2][2] = std::numeric_limits<float>::quiet_NaN();
        require(tetherCapture(familiar.data()).output.empty(), "Non-finite native point was sent");
        points[2][2] = -6;
        for (auto [offset, value] : {std::pair{0xcu, 3u}, {0xcu, 8192u}, {0x14u, 257u}}) {
            field<unsigned>(tether.data(), offset) = value;
            require(tetherCapture(familiar.data()).output.empty(), "Invalid native deque accepted");
            tether = nativeTether;
        }
        field<unsigned>(tether.data(), 0x14) = 0;
        require(tetherCapture(familiar.data()).output == hexBytes("0000"),
                "Empty tether with retained native capacity was lost");
        field<Address>(tether.data(), 8) = 0;
        field<unsigned>(tether.data(), 0xc) = 0;
        require(tetherCapture(familiar.data()).output == hexBytes("0000"),
                "Unallocated empty native tether was rejected");
        tether = nativeTether;
        const std::array<float, 2> offset{};
        const auto renderAbi =
            native_fixture::call(image + renderEntry, familiar.data(), {address(offset.data()), 0});
        require(renderAbi.balanced && renderAbi.preserved, "Tether render violated thiscall ABI");
        auto preparedLua = argument(familiar.data());
        visuals::prepareEntity(&preparedLua);
        require(preparedLua.success && prepares == 0, "Non-Needle entity ran pose preparation");
        field<unsigned>(familiar.data(), 0x28) = 881;
        visuals::prepareEntity(&preparedLua);
        require(preparedLua.success && prepares == 1 && prepared == familiar.data(),
                "Needle visual preparation used the wrong receiver or version entry");
        replica = true;
        visuals::prepareEntity(&preparedLua);
        require(!preparedLua.success && prepares == 1, "Replica ran Needle visual preparation");
        const auto prepareAbi = native_fixture::call(image + prepareEntry, familiar.data(), {});
        require(prepareAbi.balanced && prepareAbi.preserved && prepares == 2,
                "Needle prepare violated its ECX/no-stack-argument ABI");
        field<unsigned>(familiar.data(), 0x28) = 3;
        for (auto size : {4u, 0x11cu}) {
            auto invalid = argument(familiar.data());
            invalid.sizes[1] = size;
            visuals::familiarTether(&invalid);
            require(invalid.borrowed.empty(), "Owned Sprite accepted as familiar identity");
        }
        field<Address>(familiar.data(), extraOffset) = 0;
        require(tetherCapture(familiar.data()).borrowed.empty(),
                "Removed component survived subsequent capture");
        field<Address>(familiar.data(), extraOffset) = address(body.data());
        require(bodyCapture(familiar.data()).borrowed.size() == 5 &&
                    tetherCapture(familiar.data()).borrowed.empty(),
                "Replacement component retained prior familiar state");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout
            << "Body layers, tether snapshots, borrowed lifetime and native visual ABI passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

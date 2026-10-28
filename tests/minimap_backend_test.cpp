#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/minimap.cpp"
#include <cstring>
#include <iostream>
#include <limits>
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned gameGlobal = 0x7fd65c, renderer = 0x7c7a30, mapOffset = 0x1a2ab0;
constexpr unsigned roomOffset = 0x18194, dimensionOffset = 0x1819c;
constexpr unsigned widthOffset = 0x80, heightOffset = 0x84, textureEntry = 0x55f990;
constexpr std::array<unsigned, 4> entries{0x4e55f0, 0x4e5e50, 0x4e2e40, 0x565030};
#else
constexpr unsigned gameGlobal = 0x871678, renderer = 0x8798e0, mapOffset = 0x25ecc;
constexpr unsigned roomOffset = 0x18304, dimensionOffset = 0x1830c;
constexpr unsigned widthOffset = 0x10, heightOffset = 0x14, textureEntry = 0x1000;
constexpr std::array<unsigned, 4> entries{0x58dba0, 0x58e4d0, 0x58b5e0, 0x619180};
#endif
namespace {
namespace map = isaac::engine::native_minimap;
using Address = std::uintptr_t;
unsigned char* image = nullptr;
void* currentMap = nullptr;
int localSlot = -1;
unsigned viewDepth = 0, pickupDepth = 0, renders = 0, overlays = 0, updates = 0, textures = 0;
bool failCache = false, failRender = false, nested = false;
std::vector<std::string> events;
std::array<unsigned char, 0x90> texture{};
std::array<Address, 16> vtable{};
std::array<float, 9> source{};
std::array<float, 12> destination{};
std::array<std::array<float, 4>, 4> colors{};
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* object) {
    return reinterpret_cast<Address>(object);
}
void jump(unsigned rva, void* function) {
    auto* entry = image + rva;
    std::memset(entry, 0x90, 16);
    entry[0] = 0xe9;
    auto relative = address(function) - address(entry + 5);
    std::memcpy(entry + 1, &relative, 4);
}
void __attribute__((fastcall)) updateNative(void* value, void*) {
    require(value == currentMap && viewDepth, "Minimap update lost local room context");
    ++updates;
}
void __attribute__((fastcall)) cacheNative(void* value, void*) {
    require((address(value) == address(currentMap) + 0x18 ||
             address(value) == address(currentMap) + 0x178) &&
                viewDepth && pickupDepth,
            "Minimap cache lost borrowed room/pickup context");
    events.push_back(address(value) == address(currentMap) + 0x18 ? "small" : "large");
    if (failCache)
        throw std::runtime_error("Fixture cache failure");
}
void __attribute__((fastcall)) flushNative(void* value, void*, bool all) {
    require(value == image + renderer && !all && viewDepth && !pickupDepth,
            "Minimap flush changed renderer, ABI or ordering");
    events.push_back("flush");
}
#ifdef ISAAC_LAN_TEST_J835
void* __attribute__((fastcall)) textureNative(void* value, void*, const float* quad,
                                              const float* dest, const float* a, const float* b,
                                              const float* c, const float* d) {
    require(a == colors[0].data() && b == colors[1].data() && c == colors[2].data() &&
                d == colors[3].data(),
            "J835 draw lost a corner color or used the J460 ABI");
#else
void* __attribute__((fastcall)) textureNative(void* value, void*, const void* quad,
                                              const void* dest, bool transparent) {
    require(transparent, "J460 draw lost transparency argument");
#endif
    require(value == texture.data() && quad == source.data() && dest == destination.data(),
            "Texture draw changed borrowed inputs");
    ++textures;
    return reinterpret_cast<void*>(0x12345678);
}
void callTexture() {
#ifdef ISAAC_LAN_TEST_J835
    const auto result = native_fixture::call(
        image + textureEntry, texture.data(),
        {address(source.data()), address(destination.data()), address(colors[0].data()),
         address(colors[1].data()), address(colors[2].data()), address(colors[3].data())});
#else
    const auto result =
        native_fixture::call(image + textureEntry, texture.data(),
                             {address(source.data()), address(destination.data()), 1});
#endif
    require(result.balanced && result.preserved && result.eax == 0x12345678,
            "Minimap texture hook corrupted return value, stack or registers");
}
void __attribute__((fastcall)) renderNative(void* value, void*) {
    require(value == currentMap && map::activeMap == address(currentMap),
            "Minimap render lost its scope");
    ++renders;
    if (failRender)
        throw std::runtime_error("Fixture render failure");
    if (nested) {
        nested = false;
        map::minimapRender(currentMap, nullptr);
        require(map::activeMap == address(currentMap), "Nested minimap lost outer scope");
    }
    callTexture();
}
void overlay() {
    ++overlays;
}
void expectEvents(std::initializer_list<const char*> expected) {
    std::vector<std::string> values(expected.begin(), expected.end());
    require(events == values, "Minimap cache was rebuilt while rendering or flushed too late");
    events.clear();
}
void setSource(bool pixels) {
    const float size = pixels ? 100.0f : 1.0f;
    source = {0, 0, size, 0, 0, size, size, size, 0};
#ifdef ISAAC_LAN_TEST_J835
    field<unsigned>(source.data(), 0x20) = pixels ? 0 : 1;
#else
    field<unsigned>(source.data(), 0x20) = pixels ? 1 : 0;
#endif
}
} // namespace
namespace isaac::runtime {
int localViewSlot() {
    return localSlot;
}
} // namespace isaac::runtime
namespace isaac::rooms {
void withView(const std::function<void()>& fn, bool) {
    struct Restore {
        ~Restore() {
            --viewDepth;
        }
    } restore;
    ++viewDepth;
    fn();
}
void withMapPickups(const std::function<void()>& fn) {
    struct Restore {
        ~Restore() {
            --pickupDepth;
        }
    } restore;
    ++pickupDepth;
    fn();
}
} // namespace isaac::rooms
int main() {
    try {
        image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, 0x880000, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate minimap fixture");
        const std::array<void*, 4> functions{
            reinterpret_cast<void*>(updateNative), reinterpret_cast<void*>(renderNative),
            reinterpret_cast<void*>(cacheNative), reinterpret_cast<void*>(flushNative)};
        for (unsigned i = 0; i < entries.size(); ++i)
            jump(entries[i], functions[i]);
        jump(textureEntry, reinterpret_cast<void*>(textureNative));
        FlushInstructionCache(GetCurrentProcess(), image, 0x880000);
        require(!map::install(0, overlay), "Null image installed minimap hooks");
        for (unsigned conflict = 0; conflict < 3; ++conflict) {
            auto* target = image + entries[conflict];
            require(MH_CreateHook(target, functions[0], nullptr) == MH_OK,
                    "Create foreign minimap hook");
            require(!map::install(address(image), overlay) && !map::installed && !map::image,
                    "Partial minimap install survived conflict");
            require(MH_CreateHook(target, functions[0], nullptr) == MH_ERROR_ALREADY_CREATED,
                    "Minimap rollback removed foreign hook");
            for (unsigned i = 0; i < conflict; ++i) {
                require(MH_CreateHook(image + entries[i], functions[0], nullptr) == MH_OK,
                        "Rollback retained minimap hook");
                require(MH_RemoveHook(image + entries[i]) == MH_OK,
                        "Remove minimap rollback probe");
            }
            require(MH_RemoveHook(target) == MH_OK, "Remove foreign minimap hook");
        }
        require(map::install(address(image), overlay) && !map::install(address(image), overlay),
                "Minimap install retry/duplicate failure");
        std::vector<unsigned char> game(mapOffset + 0x800, 0);
        currentMap = game.data() + mapOffset;
        field<Address>(image, gameGlobal) = address(game.data());
        field<int>(game.data(), roomOffset) = 14;
        field<int>(game.data(), dimensionOffset) = 1;
        vtable[4] = address(image + textureEntry);
        field<Address>(texture.data(), 0) = address(vtable.data());
        field<int>(texture.data(), widthOffset) = 100;
        field<int>(texture.data(), heightOffset) = 100;
        for (unsigned offset : {0x18u, 0x178u}) {
            auto* config = static_cast<unsigned char*>(currentMap) + offset;
            field<Address>(config, 0x114) = address(texture.data());
            field<float>(config, 0x124) = 8;
            field<float>(config, 0x128) = 18;
            field<float>(config, 0x130) = 2;
            field<float>(config, 0x140) = 50;
            field<float>(config, 0x144) = 50;
        }
        destination = {100, 200, 300, 200, 100, 400, 300, 400, 1, 1, 1, 0.5f};
        for (auto& color : colors)
            color = {1, 1, 1, 0.5f};
        setSource(false);
        using Invoke = void(__attribute__((thiscall))*)(void*);
        const auto update = reinterpret_cast<Invoke>(image + entries[0]);
        const auto render = reinterpret_cast<Invoke>(image + entries[1]);
        const auto cache = reinterpret_cast<Invoke>(image + entries[2]);
        const auto originalGame = game;
        map::setPlayers(false, 0, {});
        cache(static_cast<unsigned char*>(currentMap) + 0x18);
        expectEvents({"small"});
        require(MH_CreateHook(image + textureEntry, reinterpret_cast<void*>(textureNative),
                              nullptr) == MH_OK,
                "Create foreign texture hook");
        render(currentMap);
        require(MH_CreateHook(image + textureEntry, reinterpret_cast<void*>(textureNative),
                              nullptr) == MH_ERROR_ALREADY_CREATED,
                "Minimap removed foreign texture hook");
        require(MH_RemoveHook(image + textureEntry) == MH_OK, "Remove foreign texture hook");
        require(map::frameMarkers().empty() && map::minimapViews().empty() && !overlays,
                "Offline minimap produced LAN markers");
        localSlot = 0;
        map::setPlayers(true, 4, {{{14, 1}, {15, 1}, {27, 2}, {999, 1}}});
        update(currentMap);
        map::prepareView();
        expectEvents({"flush", "large"});
        require(!viewDepth && !pickupDepth && updates == 1,
                "Minimap update retained borrowed view");
        render(currentMap);
        expectEvents({});
        require(map::frameMarkers().size() == 4 && map::minimapViews().size() == 2 && overlays == 1,
                "Minimap projection included another dimension or invalid cell");
        const auto first = map::frameMarkers()[0], second = map::frameMarkers()[1];
        require(first.slot == 0 && first.x == 200 && first.y == 300 && first.alpha == 0.5f &&
                    second.x == 220 && second.y == 300,
                "Minimap source units, texture dimensions or native alpha were misread");
        const auto view = map::minimapViews()[0];
        require(view.x == 180 && view.y == 260 && view.cellWidth == 20 && view.cellHeight == 40 &&
                    view.dimension == 1,
                "Minimap exported wrong room-grid origin");
        map::clearMarkers();
        map::prepareView();
        expectEvents({});
        setSource(true);
        render(currentMap);
        require(map::frameMarkers().size() == 4 && map::frameMarkers()[0].x == first.x &&
                    map::frameMarkers()[0].y == first.y,
                "Pixel and normalized source quads disagree");
        require(game == originalGame, "Minimap observation wrote native resources");
        map::clearMarkers();
        callTexture();
        require(map::frameMarkers().empty(), "Unrelated texture draw leaked into minimap");
        field<int>(game.data(), roomOffset) = 27;
        failCache = true;
        try {
            map::prepareView();
            require(false, "Cache fixture did not fail");
        } catch (const std::runtime_error& e) {
            require(std::string(e.what()) == "Fixture cache failure", "Unexpected cache error");
        }
        expectEvents({"flush", "small"});
        require(!viewDepth && !pickupDepth, "Failed cache retained room/pickup scope");
        failCache = false;
        map::prepareView();
        expectEvents({"flush", "small", "flush", "large"});
        failRender = true;
        try {
            render(currentMap);
            require(false, "Render fixture did not fail");
        } catch (const std::runtime_error& e) {
            require(std::string(e.what()) == "Fixture render failure", "Unexpected render error");
        }
        require(!map::activeMap, "Failed render retained an active minimap");
        failRender = false;
        nested = true;
        render(currentMap);
        require(!map::activeMap, "Nested render retained an active minimap");
        map::setPlayers(false, 0, {});
        require(map::frameMarkers().empty() && map::minimapViews().empty(),
                "Disconnect retained old map projection");
        map::setPlayers(true, 1, {{{14, 1}}});
        map::prepareView();
        expectEvents({"flush", "small", "flush", "large"});
        auto replacement = game;
        currentMap = replacement.data() + mapOffset;
        field<Address>(image, gameGlobal) = address(replacement.data());
        map::prepareView();
        expectEvents({"flush", "small", "flush", "large"});
        map::clearMarkers();
        destination[0] = std::numeric_limits<float>::quiet_NaN();
        render(currentMap);
        require(map::frameMarkers().empty() && map::minimapViews().empty(),
                "Non-finite native quad escaped into the overlay");
        field<Address>(image, gameGlobal) = 0;
        map::prepareView();
        expectEvents({});
        for (unsigned i = 0; i < 3; ++i)
            require(MH_RemoveHook(image + entries[i]) == MH_OK, "Remove minimap hook");
        require(MH_RemoveHook(image + textureEntry) == MH_OK && MH_Uninitialize() == MH_OK,
                "Remove texture hook");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout << "Minimap cache ordering, projection, native ABI and cleanup passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

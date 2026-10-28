#include "test_support.h"
#include "engine/versions/common/bootstrap.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned roomOffset = 0x18190, playersOffset = 0x1ba50, frameOffset = 0x1a30dc;
constexpr unsigned positionOffset = 0x294, previousOffset = 0x29c, interpolatedOffset = 0x16d;
#else
#include "engine/versions/j460/room_probe.cpp"
namespace backend = isaac::engine::j460;
constexpr unsigned roomOffset = 0x18300, playersOffset = 0x1baa8, frameOffset = 0x264f8;
constexpr unsigned positionOffset = 0x33c, previousOffset = 0x344, interpolatedOffset = 0x175;
#endif
#include <map>
#include <vector>
struct lua_State {
    std::array<long long, 4> args{};
    bool result = false;
    isaac::lua::Function pushed = nullptr;
    std::map<std::string, isaac::lua::Function> functions;
};
extern "C" {
__declspec(dllexport) long long luaL_checkinteger(lua_State* L, int index) {
    return L->args.at(index - 1);
}
__declspec(dllexport) void lua_pushboolean(lua_State* L, int value) {
    L->result = value;
}
__declspec(dllexport) void lua_pushcclosure(lua_State* L, isaac::lua::Function fn, int) {
    L->pushed = fn;
}
__declspec(dllexport) void lua_setfield(lua_State* L, int, const char* name) {
    L->functions[name] = L->pushed;
}
__declspec(dllexport) void lua_pushvalue(lua_State*, int) {}
__declspec(dllexport) int lua_pcallk(lua_State*, int, int, int, std::intptr_t,
                                     isaac::lua::Continuation) {
    return 0;
}
}
namespace {
namespace bootstrap = isaac::engine::bootstrap;
using Address = std::uintptr_t;
using NativeCall = isaac::rooms::RoomCall;
std::vector<std::string> events;
std::vector<std::string> logs;
bool managed = false, halfAllowed = true, failHalf = false, failRender = false;
void* failingRoom = nullptr;
int inputView = -1, localSlot = 0;
unsigned char* image;
std::vector<unsigned char> game(frameOffset + 32);
std::array<unsigned char, 0x1300> foreground{}, background{};
std::array<std::array<unsigned char, 0x400>, 2> entities{};
std::array<Address, 3> renderList{};
std::array<Address, 2> players{};
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void log(const std::string& line) {
    logs.push_back(line);
}
void expect(std::initializer_list<std::string> values) {
    require(events == std::vector<std::string>(values), "Game loop call order changed");
    events.clear();
}
void __attribute__((thiscall)) nativeUpdate(void* room) {
    require(room == foreground.data() || room == background.data(), "Room update ABI lost ECX");
    events.emplace_back(room == foreground.data() ? "update.foreground" : "update.background");
    if (room == failingRoom)
        throw std::runtime_error("native update failure");
}
void __attribute__((thiscall)) nativeRender(void* self) {
    require(self == game.data() && inputView == localSlot, "Rendering lost Game or local input");
    const auto room = field<Address>(self, roomOffset);
    events.emplace_back(room == reinterpret_cast<Address>(background.data()) ? "render.background"
                                                                             : "render.foreground");
    if (failRender)
        throw std::runtime_error("native render failure");
}
void nativeHalf() {
    events.emplace_back(field<Address>(game.data(), roomOffset) ==
                                reinterpret_cast<Address>(background.data())
                            ? "half.background"
                            : "half.foreground");
    if (failHalf)
        throw std::runtime_error("native half failure");
}
void jump(unsigned rva, Address fn) {
    image[rva] = 0xe9;
    const auto delta = fn - reinterpret_cast<Address>(image + rva + 5);
    std::memcpy(image + rva + 1, &delta, 4);
    std::memset(image + rva + 5, 0x90, 11);
}
void setup() {
    bootstrap::halfUpdate();
    bootstrap::restorePositions();
    require(events.empty() && bootstrap::installRendering() == 20 &&
                bootstrap::installUpdates(0, log) == 16,
            "Uninstalled loop became active");
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, 0x940000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Allocate isolated bootstrap fixture");
    jump(backend::entry::roomUpdate, reinterpret_cast<Address>(nativeUpdate));
    jump(backend::entry::gameRender, reinterpret_cast<Address>(nativeRender));
    jump(backend::entry::gameUpdateHalf, reinterpret_cast<Address>(nativeHalf));
    FlushInstructionCache(GetCurrentProcess(), image, 0x940000);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(game.data(), roomOffset) = reinterpret_cast<Address>(foreground.data());
    field<int>(game.data(), roomOffset + 4) = 84;
    field<Address>(game.data(), playersOffset) = reinterpret_cast<Address>(players.data());
    field<Address>(game.data(), playersOffset + 4) = reinterpret_cast<Address>(players.data() + 2);
    field<Address>(game.data(), playersOffset + 8) = reinterpret_cast<Address>(players.data() + 2);
    field<int>(game.data(), 0) = 1;
    field<unsigned>(game.data(), frameOffset) = 5;
    field<unsigned>(foreground.data(), 0x11f0) = UINT32_MAX - 1;
    auto* first = image + backend::entry::roomUpdate;
    auto* second = image + backend::entry::gameUpdateHalf;
    require(MH_CreateHook(second, reinterpret_cast<void*>(nativeHalf), nullptr) == MH_OK,
            "Create foreign half-update hook");
    require(bootstrap::installUpdates(reinterpret_cast<Address>(image), log) == 17,
            "Partial update installation succeeded");
    require(MH_CreateHook(first, reinterpret_cast<void*>(nativeUpdate), nullptr) == MH_OK,
            "Failed update group retained its first hook");
    require(MH_RemoveHook(first) == MH_OK &&
                MH_CreateHook(second, reinterpret_cast<void*>(nativeHalf), nullptr) ==
                    MH_ERROR_ALREADY_CREATED,
            "Rollback removed a foreign hook");
    require(MH_RemoveHook(second) == MH_OK &&
                bootstrap::installUpdates(reinterpret_cast<Address>(image), log) == 0,
            "Update group could not retry");
    require(bootstrap::installUpdates(reinterpret_cast<Address>(image), log) == 16,
            "Duplicate updates installation succeeded");
    auto* render = image + backend::entry::gameRender;
    require(MH_CreateHook(render, reinterpret_cast<void*>(nativeRender), nullptr) == MH_OK,
            "Create foreign render hook");
    require(bootstrap::installRendering() == 20 &&
                MH_CreateHook(render, reinterpret_cast<void*>(nativeRender), nullptr) ==
                    MH_ERROR_ALREADY_CREATED,
            "Render conflict removed foreign hook");
    require(MH_RemoveHook(render) == MH_OK && bootstrap::installRendering() == 0 &&
                bootstrap::installRendering() == 20,
            "Render retry/duplicate contract changed");
}
void loop() {
    const auto update = reinterpret_cast<NativeCall>(image + backend::entry::roomUpdate);
    const auto render = reinterpret_cast<NativeCall>(image + backend::entry::gameRender);
    const auto half = reinterpret_cast<void (*)()>(image + backend::entry::gameUpdateHalf);
    for (bool virtualized : {false, true, false, true}) {
        managed = virtualized;
        update(foreground.data());
        expect({"rooms.update", "update.foreground"});
        halfAllowed = false;
        half();
        expect({"half.allowed"});
        halfAllowed = true;
        half();
        expect({"half.allowed", "half.started", "rooms.half", "half.foreground", "half.completed"});
        bootstrap::halfUpdate();
        expect({"half.allowed", "half.started", "rooms.half", "half.foreground", "half.completed"});
        localSlot = virtualized ? 1 : 0;
        render(game.data());
        expect({"input.begin", "present", "frontend.prepare", "rooms.render", "render.foreground",
                "frontend.render", "input.end"});
        require(inputView == -1 && !bootstrap::scopeActive(), "Render view escaped its scope");
        failRender = true;
        rejects([&] { render(game.data()); }, "Native render failure disappeared");
        failRender = false;
        require(inputView == -1 && events.back() == "input.end", "Failed render leaked input view");
        events.clear();
        failHalf = true;
        rejects([&] { half(); }, "Native half-update failure disappeared");
        failHalf = false;
        expect({"half.allowed", "half.started", "rooms.half", "half.foreground"});
    }
}
void positions() {
    renderList = {reinterpret_cast<Address>(entities[0].data()), 0,
                  reinterpret_cast<Address>(entities[1].data())};
    field<Address>(foreground.data(), 0x125c) = reinterpret_cast<Address>(renderList.data());
    field<unsigned>(foreground.data(), 0x1264) = renderList.size();
    for (unsigned i = 0; i < entities.size(); ++i) {
        auto* entity = entities[i].data();
        field<float>(entity, positionOffset) = 1;
        field<float>(entity, positionOffset + 4) = 2;
        field<float>(entity, previousOffset) = 12;
        field<float>(entity, previousOffset + 4) = -24;
        field<bool>(entity, interpolatedOffset) = i == 0;
    }
    bootstrap::restorePositions();
    bootstrap::restorePositions();
    require(field<float>(entities[0].data(), positionOffset) == 12 &&
                field<float>(entities[0].data(), positionOffset + 4) == -24 &&
                !field<bool>(entities[0].data(), interpolatedOffset) &&
                field<float>(entities[1].data(), positionOffset) == 1,
            "Position restore changed an uninterpolated entity or failed to clear its flag");
    field<Address>(image, backend::globals::game) = 0;
    bootstrap::restorePositions();
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(game.data(), roomOffset) = 0;
    bootstrap::restorePositions();
    field<Address>(game.data(), roomOffset) = reinterpret_cast<Address>(background.data());
    bootstrap::restorePositions();
    field<Address>(game.data(), roomOffset) = reinterpret_cast<Address>(foreground.data());
}
void probes() {
    lua_State L;
    require(bootstrap::bind(&L, GetModuleHandleW(nullptr)), "Diagnostic Lua bindings failed");
    require(L.functions.count("audit") && L.functions.count("trace_callback"),
            "Missing diagnostic API");
    L.args = {1, 84, 7, 2};
    require(L.functions.at("audit")(&L) == 1 && L.result, "Version layout audit failed");
    ++L.args[2];
    L.functions.at("audit")(&L);
    require(!L.result, "Incorrect audit inputs passed");
    L.args[0] = 1;
    for (unsigned i = 0; i < 4; ++i)
        L.functions.at("trace_callback")(&L);
    require(logs.size() == 4, "Callback trace lost its bounded logging");
#ifdef ISAAC_LAN_TEST_J835
    require(L.functions.size() == 2, "Original backend exposed an unaudited room experiment");
#else
    require(L.functions.size() == 6, "J460 experiment bindings were dropped");
    // Exercise the moved experiment with borrowed fixture rooms. Allocation,
    // native construction and destruction are not simulated here.
    backend::backgroundRoom = reinterpret_cast<Address>(background.data());
    backend::backgroundIndex = 85;
    const auto originalPlayers = std::array<Address, 3>{
        field<Address>(game.data(), playersOffset), field<Address>(game.data(), playersOffset + 4),
        field<Address>(game.data(), playersOffset + 8)};
    managed = false;
    const auto update = reinterpret_cast<NativeCall>(image + backend::entry::roomUpdate);
    const auto render = reinterpret_cast<NativeCall>(image + backend::entry::gameRender);
    update(foreground.data());
    expect({"rooms.update", "update.foreground", "update.background"});
    for (auto* failed : {foreground.data(), background.data()}) {
        failingRoom = failed;
        rejects([&] { update(foreground.data()); }, "Probe update failure disappeared");
        failingRoom = nullptr;
        events.clear();
        require(!bootstrap::scopeActive() && field<Address>(game.data(), roomOffset) ==
                                                 reinterpret_cast<Address>(foreground.data()),
                "Failed experiment update retained its background room");
        for (unsigned i = 0; i < 3; ++i)
            require(field<Address>(game.data(), playersOffset + i * 4) == originalPlayers[i],
                    "Failed experiment update retained a truncated roster");
    }
    bootstrap::halfUpdate();
    expect({"half.allowed", "half.started", "rooms.half", "half.foreground", "half.background",
            "half.completed"});
    localSlot = 1;
    render(game.data());
    expect({"input.begin", "present", "frontend.prepare", "rooms.render", "render.background",
            "frontend.render", "input.end"});
    failRender = true;
    rejects([&] { render(game.data()); }, "Probe render failure disappeared");
    failRender = false;
    events.clear();
    require(!bootstrap::scopeActive() && inputView == -1 &&
                field<Address>(game.data(), roomOffset) ==
                    reinterpret_cast<Address>(foreground.data()) &&
                field<int>(game.data(), roomOffset + 4) == 84,
            "Experiment leaked its room scope after failure");
    for (unsigned i = 0; i < 3; ++i)
        require(field<Address>(game.data(), playersOffset + i * 4) == originalPlayers[i],
                "Experiment changed the native roster's allocation");
    managed = true;
    update(foreground.data());
    expect({"rooms.update", "update.foreground"});
    bootstrap::halfUpdate();
    expect({"half.allowed", "half.started", "rooms.half", "half.foreground", "half.completed"});
    backend::backgroundRoom = 0;
#endif
}
} // namespace
namespace isaac::rooms {
bool update(void* room, RoomCall original) {
    events.emplace_back("rooms.update");
    if (managed)
        original(room);
    return managed;
}
bool render(void* game, RoomCall original, int slot) {
    require(slot == localSlot, "Room renderer used another player's slot");
    events.emplace_back("rooms.render");
    if (managed)
        original(game);
    return managed;
}
bool half(void (*original)()) {
    events.emplace_back("rooms.half");
    if (managed)
        original();
    return managed;
}
} // namespace isaac::rooms
namespace isaac::input {
ViewScope::ViewScope(int slot) : previous(inputView) {
    events.emplace_back("input.begin");
    inputView = slot;
}
ViewScope::~ViewScope() {
    inputView = previous;
    events.emplace_back("input.end");
}
} // namespace isaac::input
namespace isaac::runtime {
int localViewSlot() {
    return localSlot;
}
void present() {
    events.emplace_back("present");
}
bool halfAllowed() {
    events.emplace_back("half.allowed");
    return ::halfAllowed;
}
void halfStarted() {
    events.emplace_back("half.started");
}
void halfCompleted() {
    events.emplace_back("half.completed");
}
} // namespace isaac::runtime
namespace isaac::frontend {
void prepareView() {
    events.emplace_back("frontend.prepare");
}
void render() {
    events.emplace_back("frontend.render");
}
} // namespace isaac::frontend
int main() {
    try {
        setup();
        loop();
        positions();
        probes();
        require(MH_Uninitialize() == MH_OK, "Remove loop fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS game loop ABI, hook rollback, update/render order and room scopes");
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "%s\n", e.what());
        return 1;
    }
}

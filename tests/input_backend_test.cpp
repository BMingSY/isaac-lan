// Standalone x86 native queries feed the shared input route and its real wire
// capture. No game executable or native code copied from it is loaded.
#include "test_support.h"
#include "engine/versions/common/input.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#else
#include "engine/versions/j510/entrypoints.h"
#endif
#include <MinHook.h>
#include <array>
#include <cstring>

struct lua_State {
    long long controller = -1;
    std::string bytes;
};
namespace {
int viewer = 1;
bool modal = false, replica = false;
std::vector<isaac::rooms::SavedLocation> locations;
} // namespace
namespace isaac::runtime {
int localViewSlot() {
    return viewer;
}
bool replica() {
    return ::replica;
}
void pollLocalConsole() {}
void refreshAutomation(std::uint32_t) {}
} // namespace isaac::runtime
namespace isaac::frontend {
bool capturesInput() {
    return modal;
}
} // namespace isaac::frontend
namespace isaac::rooms {
std::vector<SavedLocation> captureLocations() {
    return locations;
}
} // namespace isaac::rooms
namespace isaac::engine::items {
void grantStartingRewards(void*, unsigned) {
    throw std::runtime_error("Input routing fixture must not create actors");
}
} // namespace isaac::engine::items
namespace {
namespace input = isaac::input;
namespace lan = isaac::lan;
namespace mouse = isaac::engine::native_mouse;
#ifdef ISAAC_LAN_TEST_J835
namespace backend = isaac::engine::j835;
constexpr unsigned rosterOffset = 0x1ba50, controllerOffset = 0x154c, pauseOffset = 0x10203c;
constexpr unsigned frameOffset = 0x4a264, xOffset = 0x294, yOffset = 0x298;
constexpr int keyboardDevice = 0, restartAction = 16, resumeSelection = 1;
#else
namespace backend = isaac::engine::j510;
constexpr unsigned rosterOffset = 0x1baa8, controllerOffset = 0x161c, pauseOffset = 0x23a7c;
constexpr unsigned frameOffset = 0x4ae94, xOffset = 0x33c, yOffset = 0x340;
constexpr int keyboardDevice = -2, restartAction = 18, resumeSelection = 0;
#endif
using Address = std::uintptr_t;
constexpr unsigned imageSize = privateGameImageBytes;
unsigned char* image;
std::vector<unsigned char> game(0x190000), manager(frameOffset + sizeof(unsigned));
std::array<std::array<unsigned char, 0x2200>, 4> players{};
std::array<Address, 4> roster;
#ifndef ISAAC_LAN_TEST_J835
std::array<Address, 64> vtable{};
#endif
std::array<std::array<float, 33>, 5> values{};
std::array<std::uint32_t, 5> edges{};
unsigned physicalCalls;
struct Request {
    int action, controller;
};
std::vector<Request> requests;
void log(const std::string&) {}
template <class T> T& field(void* p, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(p) + offset);
}
Address base() {
    return reinterpret_cast<Address>(image);
}
void* receiver() {
    return image + backend::globals::inputManager;
}
float readPhysical(void* object, int action, int controller, int* source, bool edge) {
    require(object == receiver() && action >= 0 && action < 33 &&
                controller >= std::min(-1, keyboardDevice) && controller < 5,
            "Native input receiver or parameter ABI mismatch");
    ++physicalCalls;
    requests.push_back({action, controller});
    float result = 0;
    for (int i = 0; i < 5; ++i) {
        const int device = i == 0 ? keyboardDevice : i;
        if (controller != -1 && controller != device)
            continue;
        const float next =
            edge ? float(action < 32 && (edges[i] & (1u << action)) != 0) : values[i][action];
        if (next > result) {
            result = next;
            if (source)
                *source = i + 100;
        }
    }
    return result;
}
#ifdef ISAAC_LAN_TEST_J835
bool __attribute__((thiscall)) pressed(void* object, int action, int controller, int* source) {
    return readPhysical(object, action, controller, source, false) != 0;
}
bool __attribute__((thiscall)) triggered(void* object, int action, int controller, int* source) {
    return readPhysical(object, action, controller, source, true) != 0;
}
float __attribute__((thiscall)) value(void* object, int action, int controller, int* source) {
    return readPhysical(object, action, controller, source, false);
}
#else
bool __attribute__((thiscall)) query(void* object, int controller, void* callback,
                                     const int* action, void* result, int* source) {
    const auto kind = reinterpret_cast<Address>(callback) - base();
    const auto value =
        readPhysical(object, *action, controller, source, kind == backend::entry::inputTriggered);
    if (result && kind == backend::entry::inputValue)
        *static_cast<float*>(result) = value;
    return value != 0;
}
#endif
float read(int controller, int action, unsigned kind, int* source = nullptr) {
#ifdef ISAAC_LAN_TEST_J835
    if (kind == backend::entry::inputValue) {
        using Value = float(__attribute__((thiscall))*)(void*, int, int, int*);
        return reinterpret_cast<Value>(image + kind)(receiver(), action, controller, source);
    }
    using Button = bool(__attribute__((thiscall))*)(void*, int, int, int*);
    return reinterpret_cast<Button>(image + kind)(receiver(), action, controller, source) ? 1 : 0;
#else
    float value = 0;
    const auto result =
        reinterpret_cast<isaac::engine::native_input::Query>(image + backend::entry::inputQuery)(
            receiver(), controller, image + kind, &action, &value, source);
    return kind == backend::entry::inputValue ? value : float(result);
#endif
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    field<std::uint32_t>(image, rva + 1) =
        static_cast<std::uint32_t>(reinterpret_cast<Address>(fn) - base() - rva - 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void* __attribute__((thiscall)) shootingEntity(void* player) {
    require(player == players[1].data(), "Mouse must query the locally selected actor");
    return nullptr;
}
bool __attribute__((thiscall)) physicalMouse(void* player, mouse::Vector* aim, bool raw) {
    require(player == players[1].data() && field<int>(player, controllerOffset) == keyboardDevice &&
                !raw,
            "Physical mouse did not borrow the local actor's keyboard identity");
    *aim = {20, -10};
    return true;
}
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Prepare native input image");
#ifdef ISAAC_LAN_TEST_J835
    patch(backend::entry::inputPressed, pressed);
    patch(backend::entry::inputTriggered, triggered);
    patch(backend::entry::inputValue, value);
#else
    patch(backend::entry::inputQuery, query);
    patch(backend::entry::playerMouseAim, physicalMouse);
    vtable[0x74 / 4] = base() + backend::entry::inputQuery;
    field<Address>(receiver()) = reinterpret_cast<Address>(vtable.data());
#endif
    patch(backend::entry::playerShootingEntity, shootingEntity);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(image, backend::globals::manager) = reinterpret_cast<Address>(manager.data());
    for (unsigned i = 0; i < players.size(); ++i) {
        roster[i] = reinterpret_cast<Address>(players[i].data());
        field<int>(players[i].data(), controllerOffset) = i + 1;
    }
    field<Address>(game.data(), rosterOffset) = reinterpret_cast<Address>(roster.data());
    field<Address>(game.data(), rosterOffset + 4) = reinterpret_cast<Address>(roster.data() + 4);
    field<Address>(game.data(), rosterOffset + 8) = reinterpret_cast<Address>(roster.data() + 4);
    input::install(base(), log, true);
    require(!input::menuTriggered(input::action::menuConfirm), "Unexpected physical confirm");
    require(input::originalQuery, "Shared input failed to install native query adapter");
    input::lua.checkInteger = [](lua_State* L, int) { return L->controller; };
    input::lua.pushLString = [](lua_State* L, const char* data, std::size_t size) {
        L->bytes.assign(data, size);
        return L->bytes.c_str();
    };
}
void mouseRouting() {
    input::reset();
    mouse::Vector result;
    require(input::mouseAim(players[1].data(), &result) == mouse::Result::passthrough,
            "Single-player mouse did not select the native path");
#ifndef ISAAC_LAN_TEST_J835
    require(input::hookMouseAim(), "Install Plus mouse ABI adapter");
    const auto call = reinterpret_cast<mouse::Aim>(image + backend::entry::playerMouseAim);
    field<int>(players[1].data(), controllerOffset) = keyboardDevice;
    require(call(players[1].data(), &result, false) && result.x == 20 && result.y == -10,
            "Plus adapter did not forward the original mouse call");
    field<int>(players[1].data(), controllerOffset) = 2;
#endif
    lan::Frame frame;
    frame.players = 2;
    frame.connected = 3;
    frame.inputs[1].pointer = {true, 500, 100};
    field<float>(players[1].data(), xOffset) = 300;
    field<float>(players[1].data(), yOffset) = 200;
    input::apply(frame);
    require(input::mouseAim(players[1].data(), &result) == mouse::Result::active &&
                result.x == 40 && result.y == -20,
            "Shared mouse replay did not use the connected player's world target");
#ifndef ISAAC_LAN_TEST_J835
    require(call(players[1].data(), &result, false) && result.x == 40 && result.y == -20,
            "Plus native mouse hook did not route accepted input");
#endif
    lan::InputFrame preview;
    preview.pointer = {true, 350, 250};
    {
        input::PresentationInputScope scope(preview, 2);
        require(input::mouseAim(players[1].data(), &result) == mouse::Result::active &&
                    result.x == 10 && result.y == 10,
                "Mouse prediction did not use its borrowed local target");
    }
    frame.connected = 1;
    input::apply(frame);
    require(input::mouseAim(players[1].data(), &result) == mouse::Result::inactive,
            "Disconnected actor retained mouse firing");
    input::reset();
}
void routing() {
    values[2][input::action::moveLeft] = 0.25f;
    edges[2] = 1u << input::action::menuConfirm;
    int source = -1;
    require(read(2, input::action::moveLeft, backend::entry::inputValue, &source) == 0.25f &&
                source == 102,
            "Unconnected play must retain physical values and source");
    lan::Frame frame;
    frame.players = 4;
    frame.connected = 0b1011;
    frame.inputs[1].values[input::action::moveLeft] = 32768;
    frame.inputs[1].values[input::action::shootUp] = 65535;
    frame.inputs[1].triggered = 1u << input::action::item;
    frame.inputs[2].values[input::action::moveLeft] = 65535;
    input::apply(frame);
    const auto before = physicalCalls;
    require(std::abs(read(2, input::action::moveLeft, backend::entry::inputValue, &source) -
                     32768.0f / 65535.0f) < 0.00001f &&
                source == 2,
            "Accepted analog input must replace physical bindings with its LAN source");
    require(read(2, input::action::item, backend::entry::inputTriggered) == 1 &&
                read(2, input::action::item, backend::entry::inputPressed) == 0,
            "Pressed and triggered input are distinct");
    require(read(2, input::action::menuUp, backend::entry::inputValue) == 1 &&
                read(3, input::action::moveLeft, backend::entry::inputValue) == 0 &&
                physicalCalls == before,
            "Menu direction composition or disconnected-peer suppression failed");
    {
        input::ViewScope local(1);
        require(read(3, input::action::moveLeft, backend::entry::inputValue, &source) == 0.25f &&
                    source == 102,
                "Local UI must use physical controls even for another actor");
    }
    lan::InputFrame preview;
    preview.values[input::action::moveLeft] = 65535;
    {
        input::PresentationInputScope prediction(preview, 2);
        require(read(2, input::action::moveLeft, backend::entry::inputValue) == 1 &&
                    read(2, input::action::item, backend::entry::inputTriggered) == 1,
                "Prediction must override movement without replacing authoritative item edges");
    }
    field<int>(game.data(), pauseOffset) = 1;
    field<int>(game.data(), pauseOffset + 8) = resumeSelection;
    input::setMenuOwner(0);
    require(read(2, input::action::moveLeft, backend::entry::inputValue) == 0,
            "Paused non-owner consumed gameplay input");
    {
        input::PauseScope local(1);
        require(read(2, input::action::menuConfirm, backend::entry::inputTriggered) == 0 &&
                    local.intent() == isaac::pause_menu::Intent::resume,
                "Physical resume was not intercepted as a session intent");
    }
    field<int>(game.data(), pauseOffset) = 0;
    input::finishUpdate();
    require(read(2, input::action::item, backend::entry::inputTriggered) == 0 &&
                read(2, input::action::moveLeft, backend::entry::inputValue) == 0 &&
                read(2, input::action::shootUp, backend::entry::inputValue) == 1,
            "Half-step after missing room context must clear edges/movement and retain held fire");
}
lan::InputFrame capture() {
    lua_State state;
    require(input::capture(&state) == 1, "Capture must return one Lua result");
    lan::Reader reader(
        std::span(reinterpret_cast<const std::uint8_t*>(state.bytes.data()), state.bytes.size()));
    const auto result = reader.input();
    lan::Writer encoded(lan::Message::input);
    encoded.input(result);
    require(encoded.bytes.size() == state.bytes.size() + 1 &&
                std::memcmp(encoded.bytes.data() + 1, state.bytes.data(), state.bytes.size()) == 0,
            "Shared capture changed the compact input wire encoding");
    return result;
}
void physicalCapture() {
    input::reset();
    values = {};
    edges = {};
    values[0][input::action::moveRight] = 0.75f;
    values[0][13] = 1;
    const auto keyboardEdges = (1u << input::action::item) | (1u << input::action::menuBack);
    edges[0] = keyboardEdges | (1u << 13);
    field<float>(players[1].data(), xOffset) = 300;
    field<float>(players[1].data(), yOffset) = 200;
    input::originalMouseAim = physicalMouse;
    const auto before = players;
    input::pollPhysicalInput();
    const auto polled = physicalCalls;
    input::pollPhysicalInput();
    require(physicalCalls == polled && players == before,
            "Physical input must sample once per render frame and restore borrowed identity");
    const auto first = capture();
    require(first.values[input::action::moveRight] == 49151 && first.values[13] == 0 &&
                first.triggered == (keyboardEdges | (1u << input::action::menuPause)) &&
                first.values[input::action::menuPause] == lan::maxInputValue &&
                first.pointer.active && first.pointer.x == 400 && first.pointer.y == 150,
            "Physical input, local map removal or pointer normalization changed");
    require(capture().triggered == 0 && input::previewPhysicalInput().values[1] == 49151,
            "A repeated capture replayed button edges or consumed held values");
    modal = true;
    ++field<unsigned>(manager.data(), frameOffset);
    require(capture().values[1] == 0 && !capture().pointer.active,
            "Open UI leaked physical input into the network");
    modal = false;
    ++field<unsigned>(manager.data(), frameOffset);
    require(capture().values[1] == 0, "Closing UI replayed held input without release");
    values = {};
    edges = {};
    input::originalMouseAim = nullptr;
    ++field<unsigned>(manager.data(), frameOffset);
    capture();
    values[0][1] = 1;
    ++field<unsigned>(manager.data(), frameOffset);
    require(capture().values[1] == 65535, "Released physical input did not recover after UI close");
}
void versionActionsAndCleanup() {
    values = {};
    edges = {};
    values[0][restartAction] = 1;
    require(input::restartHeld(), "Canonical restart was not mapped to the native keyboard");
    edges[0] = 1u << input::action::menuBack;
    require(input::menuTriggered(input::action::menuBack) &&
                !input::menuTriggered(input::action::menuBack, true),
            "Controller-only menu input consumed a keyboard edge");
    edges[1] = edges[0];
    require(input::menuTriggered(input::action::menuBack, true), "Menu ignored the first gamepad");
    edges = {};
    values = {};
#ifdef ISAAC_LAN_TEST_J835
    values[0][18] = 1; // Original mute occupies Plus's restart number.
    require(!input::restartHeld(), "Original mute was mistaken for a restart request");
    const auto before = physicalCalls;
    require(!input::menuTriggered(input::action::emote) && physicalCalls == before,
            "Missing native emote action must never query an unrelated original action");
    const auto gameBefore = game, managerBefore = manager;
    input::resetMenuPrompts();
    require(game == gameBefore && manager == managerBefore,
            "Original menu cleanup invented a persistent Plus prompt widget");
#endif
    lan::Frame frame;
    frame.players = 2;
    frame.connected = 3;
    frame.inputs[1].values[input::action::moveRight] = 65535;
    input::apply(frame);
    require(read(2, input::action::moveRight, backend::entry::inputValue) == 1, "Rejoin input");
    input::leaveLan();
    values[2][input::action::moveRight] = 0.375f;
    require(read(2, input::action::moveRight, backend::entry::inputValue) == 0.375f &&
                input::menuOwner() == 0,
            "Leaving LAN retained accepted input or pause ownership");
    input::apply(frame);
    require(read(2, input::action::moveRight, backend::entry::inputValue) == 1,
            "Installed query boundary could not be reused for another session");
    input::leaveLan();
}
} // namespace
int main() {
    setup();
    mouseRouting();
    routing();
    physicalCapture();
    versionActionsAndCleanup();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release input fixture");
}

namespace isaac::presentation::animation {
bool active() {
    return false;
}
} // namespace isaac::presentation::animation

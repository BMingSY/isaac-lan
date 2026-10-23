#include "engine/item_effects.h"
#include "engine/lua_api.h"
#include "engine/input.h"
#include "engine/frontend.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include "core/automation_input.h"
#include "core/menu_input.h"
#include <xinput.h>
#include <MinHook.h>
#include <algorithm>
#include <cstring>
#include <atomic>
#include <vector>
#include <optional>
#include <mutex>

#include "engine/versions/j460/entrypoints.h"
namespace j460 = isaac::engine::j460;

namespace isaac::input {
namespace {
std::uintptr_t image;
void (*logger)(const std::string&);
template <class T> T& at(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
std::atomic<bool> virtualDevices{false};
std::atomic<int> labButtons{-1};
std::atomic<int> labLeftTrigger{0}, labRightTrigger{0};
std::atomic<int> labThumbX{0}, labThumbY{0};
std::atomic<unsigned> labPacket{1};
constexpr WORD restartChord = XINPUT_GAMEPAD_LEFT_THUMB | XINPUT_GAMEPAD_RIGHT_THUMB |
                              XINPUT_GAMEPAD_LEFT_SHOULDER | XINPUT_GAMEPAD_RIGHT_SHOULDER;
bool labInput = false;
bool enabled = false;
bool menuConfirm = false;
bool localPauseInput = false;
pause_menu::Intent pauseIntent = pause_menu::Intent::none;
int viewSlot = -1;
const lan::InputFrame* presentationInput = nullptr;
int presentationController = -1;
struct DeviceId {
    std::uintptr_t device;
    int original, assigned;
};
std::vector<DeviceId> lanDeviceIds;
// J460's background hotplug scan and foreground polling both remove entries
// from the same native device vector. Keep the entire traversal/callback/free
// transaction exclusive, including the disconnects after leaving LAN. Locking
// only XInputGetState/GetCapabilities is too late: both callers already hold
// a device pointer. Native connect callbacks can reenter polling on this thread.
std::recursive_mutex deviceMutex;
using DeviceUpdate = void(__cdecl*)();
DeviceUpdate originalEnumerateDevices = nullptr, originalPollDevices = nullptr;
void __cdecl enumerateDevices() {
    const std::lock_guard lock(deviceMutex);
    originalEnumerateDevices();
}
void __cdecl pollDevices() {
    const std::lock_guard lock(deviceMutex);
    originalPollDevices();
}
bool hookDevices() {
    if (originalEnumerateDevices && originalPollDevices)
        return true;
    auto scan = reinterpret_cast<void*>(image + j460::entry::inputEnumerateDevices);
    auto poll = reinterpret_cast<void*>(image + j460::entry::inputPollDevices);
    const bool created =
        MH_CreateHook(scan, reinterpret_cast<void*>(enumerateDevices),
                      reinterpret_cast<void**>(&originalEnumerateDevices)) == MH_OK &&
        MH_CreateHook(poll, reinterpret_cast<void*>(pollDevices),
                      reinterpret_cast<void**>(&originalPollDevices)) == MH_OK;
    if (created && MH_QueueEnableHook(scan) == MH_OK && MH_QueueEnableHook(poll) == MH_OK &&
        MH_ApplyQueued() == MH_OK)
        return true;
    MH_RemoveHook(scan);
    MH_RemoveHook(poll);
    originalEnumerateDevices = originalPollDevices = nullptr;
    return false;
}
void restoreDeviceIds() {
    const std::lock_guard lock(deviceMutex);
    const auto manager = image + j460::globals::inputManager;
    for (auto p = at<std::uintptr_t>(manager, 8); p != at<std::uintptr_t>(manager, 12); p += 8) {
        const auto device = at<std::uintptr_t>(p, 0);
        for (const auto& saved : lanDeviceIds)
            if (saved.device == device && at<int>(device, 12) == saved.assigned)
                at<int>(device, 12) = saved.original;
    }
    lanDeviceIds.clear();
}
void assignLanDeviceIds() {
    const std::lock_guard lock(deviceMutex);
    if (!virtualDevices || !lanDeviceIds.empty())
        return;
    const auto manager = image + j460::globals::inputManager;
    std::vector<DeviceId> devices;
    for (auto p = at<std::uintptr_t>(manager, 8); p != at<std::uintptr_t>(manager, 12); p += 8) {
        const auto device = at<std::uintptr_t>(p, 0);
        if (at<int>(device, 12) > 0)
            devices.push_back({device, at<int>(device, 12), 0});
    }
    if (devices.size() < 4)
        return;
    std::sort(devices.begin(), devices.end(),
              [](const auto& a, const auto& b) { return a.original < b.original; });
    // J460 looks up controllers by InputDevice::ID in this vector. Hotplug IDs
    // increase across reconnects; LAN players require the same 1..4 on every
    // peer. Restore native IDs before returning to any non-LAN mode.
    for (unsigned i = 0; i < 4; ++i) {
        auto device = devices[i];
        device.assigned = static_cast<int>(i + 1);
        at<int>(device.device, 12) = device.assigned;
        lanDeviceIds.push_back(device);
        if (device.original != device.assigned)
            logger("input_lan_id=" + std::to_string(device.original) + "->" +
                   std::to_string(device.assigned));
    }
}
lan::Frame accepted;
unsigned pauseOwner = 0;
std::array<lan::InputFrame, 5> physicalInput;
std::array<ModalInput, 5> modalInput;
std::array<WORD, 4> previousChatButtons{};
int localChatController = 0;
std::optional<unsigned> sampledFrame;
AutomationInput automation;
unsigned renderFrame() {
    const auto manager = at<std::uintptr_t>(image, j460::globals::manager);
    return manager ? at<unsigned>(manager, 0x4abbc) : 0;
}
using GetState = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
using GetCapabilities = DWORD(WINAPI*)(DWORD, DWORD, XINPUT_CAPABILITIES*);
using SetState = DWORD(WINAPI*)(DWORD, XINPUT_VIBRATION*);
// Native and SDL input paths can resolve different XInput DLLs. Each returned
// wrapper must retain the provider it replaced, including ordinal 100.
struct XInputProvider {
    HMODULE module = nullptr;
    GetState state = nullptr, extendedState = nullptr;
    GetCapabilities capabilities = nullptr;
    SetState vibration = nullptr;
};
std::array<XInputProvider, 8> xinputProviders;
DWORD readState(GetState original, DWORD index, XINPUT_STATE* result) {
    if (labInput && labButtons >= 0 && index == 0 && result) {
        *result = {};
        result->dwPacketNumber = labPacket.load();
        result->Gamepad.wButtons = static_cast<WORD>(labButtons.load());
        result->Gamepad.bLeftTrigger = static_cast<BYTE>(labLeftTrigger.load());
        result->Gamepad.bRightTrigger = static_cast<BYTE>(labRightTrigger.load());
        result->Gamepad.sThumbLX = static_cast<SHORT>(labThumbX.load());
        result->Gamepad.sThumbLY = static_cast<SHORT>(labThumbY.load());
        return ERROR_SUCCESS;
    }
    if (!virtualDevices)
        return original ? original(index, result) : ERROR_DEVICE_NOT_CONNECTED;
    if (index >= 4 || !result)
        return ERROR_DEVICE_NOT_CONNECTED;
    // Keep physical device state in the game's controller objects. Gameplay
    // queries consume accepted network input; capture queries deliberately
    // bypass that boundary and retain the user's native controller bindings.
    if (original && original(index, result) == ERROR_SUCCESS)
        return ERROR_SUCCESS;
    // The game constructs and owns real native controller objects. Network
    // action values are supplied at the action-query boundary, after bindings.
    *result = {};
    result->dwPacketNumber = 1;
    return ERROR_SUCCESS;
}
template <std::size_t Provider> DWORD WINAPI state(DWORD index, XINPUT_STATE* result) {
    return readState(xinputProviders[Provider].state, index, result);
}
template <std::size_t Provider> DWORD WINAPI extendedState(DWORD index, XINPUT_STATE* result) {
    return readState(xinputProviders[Provider].extendedState, index, result);
}
template <std::size_t Provider>
DWORD WINAPI capabilities(DWORD index, DWORD flags, XINPUT_CAPABILITIES* result) {
    const auto original = xinputProviders[Provider].capabilities;
    if (!virtualDevices && !(labInput && labButtons >= 0 && index == 0))
        return original ? original(index, flags, result) : ERROR_DEVICE_NOT_CONNECTED;
    if (index >= 4 || !result)
        return ERROR_DEVICE_NOT_CONNECTED;
    if (original && original(index, flags, result) == ERROR_SUCCESS)
        return ERROR_SUCCESS;
    *result = {};
    result->Type = XINPUT_DEVTYPE_GAMEPAD;
    result->SubType = XINPUT_DEVSUBTYPE_GAMEPAD;
    result->Gamepad.wButtons = 0xf3ff;
    result->Gamepad.bLeftTrigger = result->Gamepad.bRightTrigger = 255;
    result->Gamepad.sThumbLX = result->Gamepad.sThumbLY = result->Gamepad.sThumbRX =
        result->Gamepad.sThumbRY = 32767;
    return ERROR_SUCCESS;
}
template <std::size_t Provider> DWORD WINAPI vibration(DWORD index, XINPUT_VIBRATION* value) {
    const auto original = xinputProviders[Provider].vibration;
    if (!virtualDevices)
        return original ? original(index, value) : ERROR_DEVICE_NOT_CONNECTED;
    return index < 4 ? ERROR_SUCCESS : ERROR_DEVICE_NOT_CONNECTED;
}
struct XInputWrappers {
    GetState state, extendedState;
    GetCapabilities capabilities;
    SetState vibration;
};
template <std::size_t... I> constexpr auto xinputWrappers(std::index_sequence<I...>) {
    return std::array<XInputWrappers, sizeof...(I)>{
        XInputWrappers{state<I>, extendedState<I>, capabilities<I>, vibration<I>}...};
}
constexpr auto providerWrappers = xinputWrappers(std::make_index_sequence<8>{});
using Query = bool(__attribute__((thiscall)) *)(void*, int, void*, const int*, void*, int*);
Query originalQuery = nullptr;
bool __attribute__((fastcall)) query(void* manager, void*, int controller, void* callback,
                                     const int* action, void* result, int* source) {
    const auto kind = reinterpret_cast<std::uintptr_t>(callback) - image;
    if (localPauseInput && enabled && action &&
        (kind == j460::entry::inputValue || kind == j460::entry::inputPressed ||
         kind == j460::entry::inputTriggered)) {
        if (pauseIntent != pause_menu::Intent::none) {
            if (kind == j460::entry::inputValue && result)
                *static_cast<float*>(result) = 0;
            return false;
        }
        const bool pressed = originalQuery(manager, -1, callback, action, result, source);
        if (pressed && kind == j460::entry::inputTriggered) {
            const auto request = pause_menu::intent(image, *action);
            if (request != pause_menu::Intent::none) {
                pauseIntent = request;
                return false;
            }
            if (pause_menu::changesController(image, *action))
                return false;
        }
        return pressed;
    }
    if (menuConfirm && kind == j460::entry::inputTriggered && action && *action == 14)
        return true;
    if (enabled && presentationInput && controller == presentationController && action &&
        ((*action >= input::action::moveLeft && *action <= input::action::shootDown) ||
         *action == input::action::drop) &&
        (kind == j460::entry::inputValue || kind == j460::entry::inputPressed ||
         kind == j460::entry::inputTriggered)) {
        const auto value = presentationInput->values[*action];
        const bool pressed = kind == j460::entry::inputTriggered
                                 ? (presentationInput->triggered & (1u << *action)) != 0
                                 : value != 0;
        if (kind == j460::entry::inputValue && result)
            *static_cast<float*>(result) = value / 65535.0f;
        if (pressed && source)
            *source = controller;
        return pressed;
    }
    // Map is a local interface action, including queries during Game::Controls
    // and Mod updates. Presentation callbacks consume this machine's controls
    // even when a Mod still caches another actor's controller index.
    if (enabled && action && (*action == 13 || viewSlot >= 0) &&
        (kind == j460::entry::inputValue || kind == j460::entry::inputPressed ||
         kind == j460::entry::inputTriggered))
        return originalQuery(manager, -1, callback, action, result, source);
    if (!enabled || controller > accepted.players || !action || *action < 0 ||
        (kind != j460::entry::inputValue && kind != j460::entry::inputPressed &&
         kind != j460::entry::inputTriggered))
        return originalQuery(manager, controller, callback, action, result, source);
    const auto& input = accepted.inputs[controller < 1 ? pauseOwner : controller - 1];
    const auto g = at<std::uintptr_t>(image, j460::globals::game);
    if (controller > 0 && !(accepted.connected & (1u << (controller - 1)))) {
        if (kind == j460::entry::inputValue && result)
            *static_cast<float*>(result) = 0;
        return false;
    }
    if (g && at<int>(g, 0x23a74) != 0 && controller > 0 &&
        static_cast<unsigned>(controller - 1) != pauseOwner) {
        if (kind == j460::entry::inputValue && result)
            *static_cast<float*>(result) = 0;
        return false;
    }
    unsigned selected = static_cast<unsigned>(*action);
    std::uint16_t value = 0;
    bool triggered = false;
    if (selected < 16) {
        value = input.values[selected];
        triggered = (input.triggered & (1u << selected)) != 0;
    } else if (selected >= 20 && selected <= 23) {
        selected -= 20;
        value = std::max(input.values[selected], input.values[selected + 4]);
        triggered = (input.triggered & ((1u << selected) | (1u << (selected + 4)))) != 0;
    }
    const bool pressed = kind == j460::entry::inputTriggered ? triggered : value != 0;
    if (kind == j460::entry::inputValue && result)
        *static_cast<float*>(result) = value / 65535.0f;
    if (pressed && source)
        *source = controller;
    return pressed;
}
bool hookQuery() {
    if (originalQuery)
        return true;
    const auto manager = image + j460::globals::inputManager;
    const auto target =
        reinterpret_cast<void*>(at<std::uintptr_t>(at<std::uintptr_t>(manager, 0), 0x74));
    logger("input_query_rva=" + std::to_string(reinterpret_cast<std::uintptr_t>(target) - image));
    return MH_CreateHook(target, reinterpret_cast<void*>(query),
                         reinterpret_cast<void**>(&originalQuery)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
using LuaFn = int(__cdecl*)(lua_State*);
isaac::lua::API lua{};
int enable(lua_State* L) {
    const bool ok = hookDevices() && hookQuery();
    if (ok)
        virtualDevices = true;
    lua.pushBoolean(L, ok);
    if (ok)
        logger("input_virtual=ENABLED");
    return 1;
}
bool exists(int index) {
    const std::lock_guard lock(deviceMutex);
    assignLanDeviceIds();
    const auto manager = image + j460::globals::inputManager;
    // The hotplug worker also updates this vector.
    for (auto p = at<std::uintptr_t>(manager, 8); p != at<std::uintptr_t>(manager, 12); p += 8)
        if (at<int>(at<std::uintptr_t>(p, 0), 12) == index)
            return true;
    return false;
}
int assign(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const auto controller = lua.checkInteger(L, 2);
    const auto g = at<std::uintptr_t>(image, j460::globals::game);
    const auto begin = at<std::uintptr_t>(g, 0x1baa8), end = at<std::uintptr_t>(g, 0x1baac);
    if (!originalQuery || slot < 0 || static_cast<unsigned>(slot) >= (end - begin) / 4 ||
        controller < 1 || controller > 4 || !exists(static_cast<int>(controller))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
    auto player = at<std::uintptr_t>(begin, static_cast<unsigned>(slot) * 4);
    reinterpret_cast<Assign>(image + j460::entry::engineRoomsAssign)(
        reinterpret_cast<void*>(player), static_cast<int>(controller), true);
    logger("input_assign slot=" + std::to_string(slot) +
           " controller=" + std::to_string(controller));
    lua.pushBoolean(L, at<int>(player, 0x1618) == controller);
    return 1;
}
int ready(lua_State* L) {
    const std::lock_guard lock(deviceMutex);
    bool available = virtualDevices && originalQuery;
    for (int controller = 1; controller <= 4; ++controller)
        available = exists(controller) && available;
    lua.pushBoolean(L, available);
    return 1;
}
int devices(lua_State* L) {
    const std::lock_guard lock(deviceMutex);
    const auto manager = image + j460::globals::inputManager;
    std::string found = "input_devices=";
    for (auto p = at<std::uintptr_t>(manager, 8); p != at<std::uintptr_t>(manager, 12); p += 8)
        found += std::to_string(at<int>(at<std::uintptr_t>(p, 0), 12)) + ",";
    logger(found);
    lua.createTable(L, 0, 5);
    for (int i = 0; i < 5; ++i) {
        lua.pushBoolean(L, exists(i));
        lua.setField(L, -2, std::to_string(i).c_str());
    }
    return 1;
}
int spawn(lua_State* L) {
    const auto type = lua.checkInteger(L, 1), controller = lua.checkInteger(L, 2);
    if (!originalQuery || type < 0 || type > 65535 || controller < 1 || controller > 4 ||
        !exists(static_cast<int>(controller))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto g = at<std::uintptr_t>(image, j460::globals::game), manager = g + 0x1baa8;
    const auto before = (at<std::uintptr_t>(manager, 4) - at<std::uintptr_t>(manager, 0)) / 4;
    using Spawn = void*(__attribute__((thiscall))*)(void*, int);
    const auto result = reinterpret_cast<Spawn>(image + j460::entry::engineInputSpawn)(
        reinterpret_cast<void*>(manager), static_cast<int>(type));
    if (!result) {
        lua.pushBoolean(L, false);
        return 1;
    }
    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
    reinterpret_cast<Assign>(image + j460::entry::engineRoomsAssign)(
        result, static_cast<int>(controller), true);
    // SpawnCoPlayer2 creates the entity; the native join/console path then
    // initializes its starting inventory, stats and companion actors.
    using Initialize = void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Initialize>(image + j460::entry::engineInputInitialize)(result);
    engine::items::grantStartingRewards(result, static_cast<unsigned>(controller - 1));
    const auto begin = at<std::uintptr_t>(manager, 0), end = at<std::uintptr_t>(manager, 4);
    const auto first = at<std::uintptr_t>(begin, 0);
    for (auto index = before; index < (end - begin) / 4; ++index) {
        const auto player = at<std::uintptr_t>(begin, index * 4);
        reinterpret_cast<Assign>(image + j460::entry::engineRoomsAssign)(
            reinterpret_cast<void*>(player), static_cast<int>(controller), true);
        at<float>(player, 0x33c) = at<float>(player, 0x344) =
            at<float>(first, 0x33c) + 12 * controller;
        at<float>(player, 0x340) = at<float>(player, 0x348) = at<float>(first, 0x340);
    }
    using GetHUD = void*(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Initialize>(image + j460::entry::engineRoomsRoomCall_5a8620)(
        reinterpret_cast<GetHUD>(image +
                                 j460::entry::engineRoomsGetHUD)(reinterpret_cast<void*>(g)));
    logger("player_spawn type=" + std::to_string(type) +
           " controller=" + std::to_string(controller));
    lua.pushInteger(L, before);
    return 1;
}
int testGamepad(lua_State* L) {
    const auto buttons = static_cast<int>(lua.checkInteger(L, 1));
    const auto left = lua.getTop(L) > 1 ? static_cast<int>(lua.checkInteger(L, 2)) : 0;
    const auto right = lua.getTop(L) > 2 ? static_cast<int>(lua.checkInteger(L, 3)) : 0;
    const auto x = lua.getTop(L) > 3 ? static_cast<int>(lua.checkInteger(L, 4)) : 0;
    const auto y = lua.getTop(L) > 4 ? static_cast<int>(lua.checkInteger(L, 5)) : 0;
    if (buttons != labButtons || left != labLeftTrigger || right != labRightTrigger ||
        x != labThumbX || y != labThumbY) {
        labButtons = buttons;
        labLeftTrigger = std::clamp(left, 0, 255);
        labRightTrigger = std::clamp(right, 0, 255);
        labThumbX = std::clamp(x, -32767, 32767);
        labThumbY = std::clamp(y, -32767, 32767);
        ++labPacket;
    }
    return 0;
}
int botInput(lua_State* L) {
    const auto active = lua.checkInteger(L, 1), buttons = lua.checkInteger(L, 2);
    const bool valid = (active == 0 || active == 1) && buttons >= 0 && buttons <= 255;
    if (valid)
        automation.set(active != 0, static_cast<std::uint8_t>(buttons), renderFrame());
    else
        automation.clear();
    lua.pushBoolean(L, valid);
    return 1;
}
void samplePhysicalInput() {
    if (!originalQuery)
        return;
    const auto manager = at<std::uintptr_t>(image, j460::globals::manager);
    if (!manager)
        return;
    const auto frame = at<unsigned>(manager, 0x4abbc);
    if (sampledFrame == frame)
        return;
    sampledFrame = frame;
    runtime::pollLocalConsole();
    runtime::refreshAutomation(frame);
    const bool capturing = frontend::capturesInput() || restartHeld();
    if (capturing) {
        automation.clear();
        physicalInput = {};
    }
    void* inputManager = reinterpret_cast<void*>(image + j460::globals::inputManager);
    for (unsigned source = 0; source < physicalInput.size(); ++source) {
        auto& input = physicalInput[source];
        for (int action = 0; action < 16; ++action) {
            float value = 0;
            originalQuery(inputManager, source,
                          reinterpret_cast<void*>(image + j460::entry::inputValue), &action, &value,
                          nullptr);
            input.values[action] =
                static_cast<std::uint16_t>(std::clamp(value, 0.0f, 1.0f) * 65535.0f + 0.5f);
            if (originalQuery(inputManager, source,
                              reinterpret_cast<void*>(image + j460::entry::inputTriggered), &action,
                              nullptr, nullptr))
                input.triggered |= 1u << action;
        }
        const auto game = at<std::uintptr_t>(image, j460::globals::game);
        if (source == 0 && game)
            keyboardPause(input, at<int>(game, 0x23a74) != 0);
        modalInput[source].filter(input, capturing);
    }
}
int capture(lua_State* L) {
    const auto controller = lua.checkInteger(L, 1);
    if (!originalQuery || controller < -1 || controller > 4) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lan::InputFrame frame;
    samplePhysicalInput();
    for (int source = controller < 0 ? 0 : static_cast<int>(controller);
         source <= (controller < 0 ? 4 : controller); ++source) {
        auto& physical = physicalInput[source];
        for (int action = 0; action < 16; ++action)
            frame.values[action] = std::max(frame.values[action], physical.values[action]);
        frame.triggered |= physical.triggered;
        physical.triggered = 0;
    }
    frame.values[13] = 0;
    frame.triggered &= ~(1u << 13);
    frame = automation.compose(frame, renderFrame(), true);
    lan::Writer writer(lan::Message::input);
    writer.input(frame);
    lua.pushLString(L, reinterpret_cast<const char*>(writer.bytes.data() + 1),
                    writer.bytes.size() - 1);
    return 1;
}
} // namespace
ViewScope::ViewScope(int slot) : previous(viewSlot) {
    viewSlot = slot;
}
ViewScope::~ViewScope() {
    viewSlot = previous;
}
PresentationInputScope::PresentationInputScope(const lan::InputFrame& input, int controller)
    : previous(presentationInput), previousController(presentationController) {
    presentationInput = &input;
    presentationController = controller;
}
PresentationInputScope::~PresentationInputScope() {
    presentationInput = previous;
    presentationController = previousController;
}
PauseScope::PauseScope(int slot)
    : view(slot), previous(localPauseInput), previousIntent(pauseIntent) {
    localPauseInput = true;
    pauseIntent = pause_menu::Intent::none;
}
PauseScope::~PauseScope() {
    localPauseInput = previous;
    pauseIntent = previousIntent;
}
pause_menu::Intent PauseScope::intent() const {
    return pauseIntent;
}
void install(std::uintptr_t base, void (*log)(const std::string&), bool installed) {
    image = base;
    logger = log;
    virtualDevices = false;
    wchar_t root[1024]{};
    if (GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", root, 1024))
        labInput = GetFileAttributesW((std::wstring(root) + L"\\.isaac-lan-lab").c_str()) !=
                   INVALID_FILE_ATTRIBUTES;
    if (!installed && GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", root, 1024))
        virtualDevices =
            GetFileAttributesW((std::wstring(root) + L"\\virtual-input.test").c_str()) !=
            INVALID_FILE_ATTRIBUTES;
}
FARPROC resolve(HMODULE module, LPCSTR name, FARPROC original) {
    // Preserve missing exports so the native loader can try its next provider.
    if (!original || !module)
        return original;
    const bool ordinal = reinterpret_cast<std::uintptr_t>(name) <= 0xffff;
    if (ordinal) {
        if (reinterpret_cast<std::uintptr_t>(name) != 100)
            return original;
        wchar_t path[1024]{};
        GetModuleFileNameW(module, path, 1024);
        std::wstring lower(path);
        std::transform(lower.begin(), lower.end(), lower.begin(), towlower);
        if (lower.find(L"xinput") == std::wstring::npos)
            return original;
    } else if (strcmp(name, "XInputGetState") && strcmp(name, "XInputGetCapabilities") &&
               strcmp(name, "XInputSetState")) {
        return original;
    }
    std::size_t index = 0;
    for (; index < xinputProviders.size(); ++index)
        if (!xinputProviders[index].module || xinputProviders[index].module == module)
            break;
    if (index == xinputProviders.size())
        return original;
    auto& provider = xinputProviders[index];
    provider.module = module;
    const auto& wrapper = providerWrappers[index];
    const auto wrap = [&](auto& saved, auto replacement, const char* symbol) {
        FARPROC result;
        memcpy(&saved, &original, sizeof(original));
        memcpy(&result, &replacement, sizeof(result));
        if (logger)
            logger(std::string("input_api=") + symbol);
        return result;
    };
    if (ordinal)
        return wrap(provider.extendedState, wrapper.extendedState, "XInputGetStateEx");
    if (strcmp(name, "XInputGetState") == 0)
        return wrap(provider.state, wrapper.state, name);
    if (strcmp(name, "XInputGetCapabilities") == 0)
        return wrap(provider.capabilities, wrapper.capabilities, name);
    return wrap(provider.vibration, wrapper.vibration, name);
}
void apply(const lan::Frame& frame) {
    accepted = frame;
    enabled = originalQuery != nullptr;
    if (!(frame.connected & (1u << pauseOwner)))
        pauseOwner = 0;
    const auto g = at<std::uintptr_t>(image, j460::globals::game);
    if (enabled && g && at<int>(g, 0x23a74) == 0) {
        for (unsigned slot = 0; slot < frame.players; ++slot)
            if (frame.inputs[slot].triggered & ((1u << 12) | (1u << 15))) {
                pauseOwner = slot;
                break;
            }
    }
    if (enabled)
        pause_menu::selectPlayer(image, runtime::localViewSlot());
}
void reset() {
    automation.clear();
    enabled = false;
    accepted = {};
    pauseOwner = 0;
    physicalInput = {};
    modalInput = {};
    previousChatButtons = {};
    localChatController = 0;
    sampledFrame.reset();
}
void clearAutomation() {
    automation.clear();
}
void resetMenuPrompts() {
    if (!image)
        return;
    const auto manager = at<std::uintptr_t>(image, j460::globals::manager);
    if (!manager)
        return;
    // J460 embeds this group in Manager. The native reset hides the previous
    // menu's BACK/SELECT papers without replacing widgets or their ownership.
    using ResetPrompts = void(__attribute__((thiscall))*)(void*, bool);
    reinterpret_cast<ResetPrompts>(image + j460::entry::managerResetButtonPrompts)(
        reinterpret_cast<void*>(manager + 0x4a950), false);
}
void finishUpdate() {
    // A network input covers one full update and its interpolation update.
    // The native input manager clears press edges between those two renders;
    // keep held values, but never replay an active/card press in the half step.
    for (auto& input : accepted.inputs)
        input.triggered = 0;
    if (!enabled || runtime::replica())
        return;
    // Room transfer finishes after the full update. Its following half update
    // must not accelerate a remote arrival with the departure room's controls.
    const auto locations = rooms::captureLocations();
    for (unsigned slot = 1; slot < accepted.players; ++slot) {
        const auto& context = accepted.inputRooms[slot];
        if (!context || slot >= locations.size() || context->index != locations[slot].index ||
            context->dimension != locations[slot].dimension)
            accepted.inputs[slot] = transitionInput(accepted.inputs[slot], true);
    }
}
void pollPhysicalInput() {
    samplePhysicalInput();
}
unsigned physicalFrame() {
    return renderFrame();
}
lan::InputFrame previewPhysicalInput() {
    samplePhysicalInput();
    lan::InputFrame preview;
    for (const auto& physical : physicalInput)
        for (unsigned action = 0; action < lan::actionCount; ++action)
            preview.values[action] = std::max(preview.values[action], physical.values[action]);
    return automation.compose(preview, renderFrame(), false);
}
unsigned menuOwner() {
    return pauseOwner;
}
void setMenuOwner(unsigned slot) {
    pauseOwner = slot;
}
void leaveLan() {
    reset();
    restoreDeviceIds();
    virtualDevices = false;
    if (logger)
        logger("input_virtual=DISABLED");
}
void prepareControllers() {
    assignLanDeviceIds();
}
void confirmOriginalMenu(void* menu, void(__attribute__((thiscall)) * update)(void*)) {
    if (!hookQuery())
        return;
    menuConfirm = true;
    update(menu);
    menuConfirm = false;
}
bool menuTriggered(int action, bool controllersOnly) {
    if (!hookQuery())
        return false;
    const int first = controllersOnly ? 1 : -1, last = controllersOnly ? lan::maxPlayers : -1;
    for (int controller = first; controller <= last; ++controller)
        if (originalQuery(reinterpret_cast<void*>(image + j460::globals::inputManager), controller,
                          reinterpret_cast<void*>(image + j460::entry::inputTriggered), &action,
                          nullptr, nullptr))
            return true;
    return false;
}
bool restartHeld() {
    const int action = input::action::restart;
    if (hookQuery())
        for (unsigned source = 0; source < physicalInput.size(); ++source)
            if (originalQuery(reinterpret_cast<void*>(image + j460::globals::inputManager), source,
                              reinterpret_cast<void*>(image + j460::entry::inputPressed), &action,
                              nullptr, nullptr))
                return true;
    const auto provider = std::find_if(xinputProviders.begin(), xinputProviders.end(),
                                       [](const auto& p) { return p.state != nullptr; });
    if (provider != xinputProviders.end())
        for (unsigned i = 0; i < 4; ++i) {
            XINPUT_STATE state{};
            if (readState(provider->state, i, &state) == ERROR_SUCCESS &&
                (state.Gamepad.wButtons & restartChord) == restartChord)
                return true;
        }
    return false;
}
bool hostMenuTriggered(int action) {
    return enabled && menuActionTriggered(accepted.inputs[0], action);
}
int chatControls(lua_State* L) {
    // Read the original physical device, before LAN's virtual controller routing.
    // L3 is a local UI shortcut; it is never transmitted as a gameplay action.
    auto& previous = previousChatButtons;
    bool toggle = false, restart = false;
    for (unsigned i = 0; i < previous.size(); ++i) {
        XINPUT_STATE state{};
        const auto provider = std::find_if(xinputProviders.begin(), xinputProviders.end(),
                                           [](const auto& p) { return p.state != nullptr; });
        if (provider != xinputProviders.end() &&
            readState(provider->state, i, &state) == ERROR_SUCCESS) {
            const auto pressed = static_cast<WORD>(state.Gamepad.wButtons & ~previous[i]);
            toggle |= (pressed & XINPUT_GAMEPAD_LEFT_THUMB) != 0;
            restart |= (state.Gamepad.wButtons & restartChord) == restartChord;
            if (pressed)
                localChatController = i + 1;
            previous[i] = state.Gamepad.wButtons;
        } else
            previous[i] = 0;
    }
    lua.createTable(L, 0, 8);
    lua.pushBoolean(L, toggle && !restart);
    lua.setField(L, -2, "chat");
    lua.pushBoolean(L, restart);
    lua.setField(L, -2, "restart");
    if (GetKeyState(VK_LMENU) < 0)
        localChatController = 0;
    lua.pushInteger(L, localChatController);
    lua.setField(L, -2, "controller");
    for (const auto& [name, action] : {std::pair{"confirm", action::menuConfirm},
                                       {"back", action::menuBack},
                                       {"left", action::menuLeft},
                                       {"right", action::menuRight},
                                       {"up", action::menuUp},
                                       {"down", action::menuDown},
                                       {"emote", action::emote}}) {
        lua.pushBoolean(L, !restart && menuTriggered(action));
        lua.setField(L, -2, name);
    }
    return 1;
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::getTop,
                           isaac::lua::Symbol::pushInteger, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::checkInteger, isaac::lua::Symbol::pushLString}))
        return false;
    auto function = [&](const char* name, LuaFn fn) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    };
    function("chat_controls", chatControls);
    function("input_virtual", enable);
    function("input_ready", ready);
    function("input_assign", assign);
    function("input_devices", devices);
    function("input_capture", capture);
    function("input_bot", botInput);
    function("players_spawn", spawn);
    if (labInput)
        function("test_gamepad", testGamepad);
    return true;
}
} // namespace isaac::input

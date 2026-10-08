#include "engine_input.h"
#include "frontend.h"
#include <xinput.h>
#include <MinHook.h>
#include <algorithm>
#include <cstring>
#include <atomic>
#include <vector>
#include <optional>

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
bool labInput = false;
bool enabled = false;
bool menuConfirm = false;
int viewSlot = -1;
struct DeviceId {
    std::uintptr_t device;
    int original, assigned;
};
std::vector<DeviceId> lanDeviceIds;
void restoreDeviceIds() {
    const auto manager = image + 0x857b18;
    for (auto p = at<std::uintptr_t>(manager, 8); p != at<std::uintptr_t>(manager, 12); p += 8) {
        const auto device = at<std::uintptr_t>(p, 0);
        for (const auto& saved : lanDeviceIds)
            if (saved.device == device && at<int>(device, 12) == saved.assigned)
                at<int>(device, 12) = saved.original;
    }
    lanDeviceIds.clear();
}
void assignLanDeviceIds() {
    if (!virtualDevices || !lanDeviceIds.empty())
        return;
    const auto manager = image + 0x857b18;
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
std::optional<unsigned> sampledFrame;
using GetState = DWORD(WINAPI*)(DWORD, XINPUT_STATE*);
using GetCapabilities = DWORD(WINAPI*)(DWORD, DWORD, XINPUT_CAPABILITIES*);
using SetState = DWORD(WINAPI*)(DWORD, XINPUT_VIBRATION*);
GetState originalState = nullptr;
GetState originalExtendedState = nullptr;
GetCapabilities originalCapabilities = nullptr;
SetState originalVibration = nullptr;
DWORD WINAPI state(DWORD index, XINPUT_STATE* result) {
    if (labInput && labButtons >= 0 && index == 0 && result) {
        *result = {};
        result->dwPacketNumber = static_cast<DWORD>(labButtons.load() + 1);
        result->Gamepad.wButtons = static_cast<WORD>(labButtons.load());
        result->Gamepad.bLeftTrigger = static_cast<BYTE>(labLeftTrigger.load());
        result->Gamepad.bRightTrigger = static_cast<BYTE>(labRightTrigger.load());
        return ERROR_SUCCESS;
    }
    if (!virtualDevices)
        return originalState ? originalState(index, result) : ERROR_DEVICE_NOT_CONNECTED;
    if (index >= 4 || !result)
        return ERROR_DEVICE_NOT_CONNECTED;
    // Keep physical device state in the game's controller objects. Gameplay
    // queries consume accepted network input; capture queries deliberately
    // bypass that boundary and retain the user's native controller bindings.
    if (originalState && originalState(index, result) == ERROR_SUCCESS)
        return ERROR_SUCCESS;
    // The game constructs and owns real native controller objects. Network
    // action values are supplied at the action-query boundary, after bindings.
    *result = {};
    result->dwPacketNumber = 1;
    return ERROR_SUCCESS;
}
DWORD WINAPI extendedState(DWORD index, XINPUT_STATE* result) {
    if (virtualDevices || (labInput && labButtons >= 0 && index == 0))
        return state(index, result);
    return originalExtendedState ? originalExtendedState(index, result)
                                 : ERROR_DEVICE_NOT_CONNECTED;
}
DWORD WINAPI capabilities(DWORD index, DWORD flags, XINPUT_CAPABILITIES* result) {
    if (!virtualDevices && !(labInput && labButtons >= 0 && index == 0))
        return originalCapabilities ? originalCapabilities(index, flags, result)
                                    : ERROR_DEVICE_NOT_CONNECTED;
    if (index >= 4 || !result)
        return ERROR_DEVICE_NOT_CONNECTED;
    if (originalCapabilities && originalCapabilities(index, flags, result) == ERROR_SUCCESS)
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
DWORD WINAPI vibration(DWORD index, XINPUT_VIBRATION* value) {
    if (!virtualDevices)
        return originalVibration ? originalVibration(index, value) : ERROR_DEVICE_NOT_CONNECTED;
    return index < 4 ? ERROR_SUCCESS : ERROR_DEVICE_NOT_CONNECTED;
}
using Query = bool(__attribute__((thiscall)) *)(void*, int, void*, const int*, void*, int*);
Query originalQuery = nullptr;
bool __attribute__((fastcall)) query(void* manager, void*, int controller, void* callback,
                                     const int* action, void* result, int* source) {
    const auto kind = reinterpret_cast<std::uintptr_t>(callback) - image;
    if (menuConfirm && kind == 0x6209e0 && action && *action == 14)
        return true;
    // Map is a local interface action, including queries during Game::Controls
    // and Mod updates. Presentation callbacks consume this machine's controls
    // even when a Mod still caches another actor's controller index.
    if (enabled && action && (*action == 13 || viewSlot >= 0) &&
        (kind == 0x620ab0 || kind == 0x620940 || kind == 0x6209e0))
        return originalQuery(manager, -1, callback, action, result, source);
    if (!enabled || controller > accepted.players || !action || *action < 0 ||
        (kind != 0x620ab0 && kind != 0x620940 && kind != 0x6209e0))
        return originalQuery(manager, controller, callback, action, result, source);
    const auto& input = accepted.inputs[controller < 1 ? pauseOwner : controller - 1];
    const auto g = at<std::uintptr_t>(image, 0x871678);
    if (controller > 0 && !(accepted.connected & (1u << (controller - 1)))) {
        if (kind == 0x620ab0 && result)
            *static_cast<float*>(result) = 0;
        return false;
    }
    if (g && at<int>(g, 0x23a74) != 0 && controller > 0 &&
        static_cast<unsigned>(controller - 1) != pauseOwner) {
        if (kind == 0x620ab0 && result)
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
    const bool pressed = kind == 0x6209e0 ? triggered : value != 0;
    if (kind == 0x620ab0 && result)
        *static_cast<float*>(result) = value / 65535.0f;
    if (pressed && source)
        *source = controller;
    return pressed;
}
bool hookQuery() {
    if (originalQuery)
        return true;
    const auto manager = image + 0x857b18;
    const auto target =
        reinterpret_cast<void*>(at<std::uintptr_t>(at<std::uintptr_t>(manager, 0), 0x74));
    logger("input_query_rva=" + std::to_string(reinterpret_cast<std::uintptr_t>(target) - image));
    return MH_CreateHook(target, reinterpret_cast<void*>(query),
                         reinterpret_cast<void**>(&originalQuery)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
using LuaFn = int(__cdecl*)(lua_State*);
struct API {
    int(__cdecl* getTop)(lua_State*);
    void(__cdecl* pushClosure)(lua_State*, LuaFn, int);
    void(__cdecl* setField)(lua_State*, int, const char*);
    void(__cdecl* pushBoolean)(lua_State*, int);
    void(__cdecl* pushInteger)(lua_State*, long long);
    const char*(__cdecl* pushLString)(lua_State*, const char*, std::size_t);
    void(__cdecl* createTable)(lua_State*, int, int);
    long long(__cdecl* checkInteger)(lua_State*, int);
} lua;
int enable(lua_State* L) {
    virtualDevices = true;
    const bool ok = hookQuery();
    lua.pushBoolean(L, ok);
    if (ok)
        logger("input_virtual=ENABLED");
    return 1;
}
bool exists(int index) {
    assignLanDeviceIds();
    const auto manager = image + 0x857b18;
    // Input enumeration and Lua callbacks run on the game's main thread.
    for (auto p = at<std::uintptr_t>(manager, 8); p != at<std::uintptr_t>(manager, 12); p += 8)
        if (at<int>(at<std::uintptr_t>(p, 0), 12) == index)
            return true;
    return false;
}
int assign(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const auto controller = lua.checkInteger(L, 2);
    const auto g = at<std::uintptr_t>(image, 0x871678);
    const auto begin = at<std::uintptr_t>(g, 0x1baa8), end = at<std::uintptr_t>(g, 0x1baac);
    if (!originalQuery || slot < 0 || static_cast<unsigned>(slot) >= (end - begin) / 4 ||
        controller < 1 || controller > 4 || !exists(static_cast<int>(controller))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
    auto player = at<std::uintptr_t>(begin, static_cast<unsigned>(slot) * 4);
    reinterpret_cast<Assign>(image + 0x3a6450)(reinterpret_cast<void*>(player),
                                               static_cast<int>(controller), true);
    logger("input_assign slot=" + std::to_string(slot) +
           " controller=" + std::to_string(controller));
    lua.pushBoolean(L, at<int>(player, 0x1618) == controller);
    return 1;
}
int devices(lua_State* L) {
    const auto manager = image + 0x857b18;
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
    const auto g = at<std::uintptr_t>(image, 0x871678), manager = g + 0x1baa8;
    const auto before = (at<std::uintptr_t>(manager, 4) - at<std::uintptr_t>(manager, 0)) / 4;
    using Spawn = void*(__attribute__((thiscall))*)(void*, int);
    const auto result = reinterpret_cast<Spawn>(image + 0x5b9cd0)(reinterpret_cast<void*>(manager),
                                                                  static_cast<int>(type));
    if (!result) {
        lua.pushBoolean(L, false);
        return 1;
    }
    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
    reinterpret_cast<Assign>(image + 0x3a6450)(result, static_cast<int>(controller), true);
    // SpawnCoPlayer2 creates the entity; the native join/console path then
    // initializes its starting inventory, stats and companion actors.
    using Initialize = void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Initialize>(image + 0x3bc740)(result);
    const auto begin = at<std::uintptr_t>(manager, 0), end = at<std::uintptr_t>(manager, 4);
    const auto first = at<std::uintptr_t>(begin, 0);
    for (auto index = before; index < (end - begin) / 4; ++index) {
        const auto player = at<std::uintptr_t>(begin, index * 4);
        reinterpret_cast<Assign>(image + 0x3a6450)(reinterpret_cast<void*>(player),
                                                   static_cast<int>(controller), true);
        at<float>(player, 0x33c) = at<float>(player, 0x344) =
            at<float>(first, 0x33c) + 12 * controller;
        at<float>(player, 0x340) = at<float>(player, 0x348) = at<float>(first, 0x340);
    }
    using GetHUD = void*(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Initialize>(image + 0x5a8620)(
        reinterpret_cast<GetHUD>(image + 0x178e0)(reinterpret_cast<void*>(g)));
    logger("player_spawn type=" + std::to_string(type) +
           " controller=" + std::to_string(controller));
    lua.pushInteger(L, before);
    return 1;
}
int testGamepad(lua_State* L) {
    labButtons = static_cast<int>(lua.checkInteger(L, 1));
    labLeftTrigger = lua.getTop(L) > 1 ? static_cast<int>(lua.checkInteger(L, 2)) : 0;
    labRightTrigger = lua.getTop(L) > 2 ? static_cast<int>(lua.checkInteger(L, 3)) : 0;
    return 0;
}
void samplePhysicalInput() {
    if (!originalQuery)
        return;
    const auto manager = at<std::uintptr_t>(image, 0x87169c);
    if (!manager)
        return;
    const auto frame = at<unsigned>(manager, 0x4abbc);
    if (sampledFrame == frame)
        return;
    sampledFrame = frame;
    if (frontend::capturesInput()) {
        physicalInput = {};
        return;
    }
    void* inputManager = reinterpret_cast<void*>(image + 0x857b18);
    for (unsigned source = 0; source < physicalInput.size(); ++source) {
        auto& input = physicalInput[source];
        for (int action = 0; action < 16; ++action) {
            float value = 0;
            originalQuery(inputManager, source, reinterpret_cast<void*>(image + 0x620ab0), &action,
                          &value, nullptr);
            input.values[action] =
                static_cast<std::uint16_t>(std::clamp(value, 0.0f, 1.0f) * 65535.0f + 0.5f);
            if (originalQuery(inputManager, source, reinterpret_cast<void*>(image + 0x6209e0),
                              &action, nullptr, nullptr))
                input.triggered |= 1u << action;
        }
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
    if (reinterpret_cast<std::uintptr_t>(name) <= 0xffff) {
        if (reinterpret_cast<std::uintptr_t>(name) == 100) {
            wchar_t path[1024]{};
            GetModuleFileNameW(module, path, 1024);
            std::wstring lower(path);
            std::transform(lower.begin(), lower.end(), lower.begin(), towlower);
            if (lower.find(L"xinput") != std::wstring::npos) {
                memcpy(&originalExtendedState, &original, sizeof(original));
                auto fn = extendedState;
                FARPROC replacement;
                memcpy(&replacement, &fn, sizeof(fn));
                if (logger)
                    logger("input_api=XInputGetStateEx");
                return replacement;
            }
        }
        return original;
    }
    FARPROC replacement = nullptr;
#define WRAP(symbol, saved, replacementFn)                                                         \
    if (strcmp(name, symbol) == 0) {                                                               \
        if (original)                                                                              \
            memcpy(&saved, &original, sizeof(original));                                           \
        auto fn = replacementFn;                                                                   \
        memcpy(&replacement, &fn, sizeof(fn));                                                     \
        if (logger)                                                                                \
            logger("input_api=" symbol);                                                           \
        return replacement;                                                                        \
    }
    WRAP("XInputGetState", originalState, state)
    WRAP("XInputGetCapabilities", originalCapabilities, capabilities)
    WRAP("XInputSetState", originalVibration, vibration)
#undef WRAP
    return original;
}
void apply(const lan::Frame& frame) {
    accepted = frame;
    enabled = originalQuery != nullptr;
    if (!(frame.connected & (1u << pauseOwner)))
        pauseOwner = 0;
    const auto g = at<std::uintptr_t>(image, 0x871678);
    if (enabled && g && at<int>(g, 0x23a74) == 0) {
        for (unsigned slot = 0; slot < frame.players; ++slot)
            if (frame.inputs[slot].triggered & ((1u << 12) | (1u << 15))) {
                pauseOwner = slot;
                break;
            }
    }
    if (enabled && g) {
        const auto begin = at<std::uintptr_t>(g, 0x1baa8), end = at<std::uintptr_t>(g, 0x1baac);
        for (auto p = begin; p != end; p += 4)
            if (at<int>(at<std::uintptr_t>(p, 0), 0x1618) == static_cast<int>(pauseOwner + 1)) {
                at<int>(g, 0x23a74 + 0xfac) = (p - begin) / 4;
                break;
            }
    }
}
void reset() {
    enabled = false;
    accepted = {};
    pauseOwner = 0;
    physicalInput = {};
    sampledFrame.reset();
}
void finishUpdate() {
    // A network input covers one full update and its interpolation update.
    // The native input manager clears press edges between those two renders;
    // keep held values, but never replay an active/card press in the half step.
    for (auto& input : accepted.inputs)
        input.triggered = 0;
}
void pollPhysicalInput() {
    samplePhysicalInput();
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
void confirmOriginalMenu(void* menu, void(__attribute__((thiscall)) * update)(void*)) {
    if (!hookQuery())
        return;
    menuConfirm = true;
    update(menu);
    menuConfirm = false;
}
bool menuTriggered(int action) {
    return hookQuery() &&
           originalQuery(reinterpret_cast<void*>(image + 0x857b18), -1,
                         reinterpret_cast<void*>(image + 0x6209e0), &action, nullptr, nullptr);
}
bool bind(lua_State* L, HMODULE module) {
#define IMPORT(field, name)                                                                        \
    do {                                                                                           \
        auto p = GetProcAddress(module, name);                                                     \
        memcpy(&lua.field, &p, sizeof(p));                                                         \
        if (!lua.field)                                                                            \
            return false;                                                                          \
    } while (false)
    IMPORT(pushClosure, "lua_pushcclosure");
    IMPORT(setField, "lua_setfield");
    IMPORT(pushBoolean, "lua_pushboolean");
    IMPORT(getTop, "lua_gettop");
    IMPORT(pushInteger, "lua_pushinteger");
    IMPORT(createTable, "lua_createtable");
    IMPORT(checkInteger, "luaL_checkinteger");
    IMPORT(pushLString, "lua_pushlstring");
#undef IMPORT
    auto function = [&](const char* name, LuaFn fn) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    };
    function("input_virtual", enable);
    function("input_assign", assign);
    function("input_devices", devices);
    function("input_capture", capture);
    function("players_spawn", spawn);
    if (labInput)
        function("test_gamepad", testGamepad);
    return true;
}
} // namespace isaac::input

// J460 native adapter. Lab launches retain explicit profile isolation; ordinary
// launches require the installer marker, J460 layout and compatible entry points.
#include <windows.h>
#include <MinHook.h>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <filesystem>
#include <fstream>
#include "runtime_net.h"
#include "engine_audio.h"
#include "engine_presentation.h"
#include "engine_rewind.h"
#include "engine_rooms.h"
#include "engine_input.h"
#include "frontend.h"
#include "game_build.h"
#include "bootstrap_profile.h"

extern "C" __declspec(dllexport) int __cdecl luaopen_isaac_lan_probe(lua_State* L);

namespace {
static_assert(sizeof(void*) == 4);
std::wstring root;
std::string profile;
std::uintptr_t image = 0;
bool initialized = false;
bool isolated = true;
// A lab focus driver can temporarily join Win32 input queues. GLFW must never
// dereference a window property belonging to the other game process.
HWND WINAPI localActiveWindow() {
    HWND window = GetActiveWindow();
    DWORD process = 0;
    if (window)
        GetWindowThreadProcessId(window, &process);
    return process == GetCurrentProcessId() ? window : nullptr;
}
using GetProc = FARPROC(WINAPI*)(HMODULE, LPCSTR);
GetProc originalGetProc = GetProcAddress;

void log(const std::string& line) {
    const auto file = root + L"\\probe.log";
    HANDLE out = CreateFileW(file.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                             nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE)
        return;
    DWORD written = 0;
    const auto text = line + "\r\n";
    WriteFile(out, text.data(), static_cast<DWORD>(text.size()), &written, nullptr);
    CloseHandle(out);
}

std::string utf8(const std::wstring& s) {
    int size = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0,
                                   nullptr, nullptr);
    std::string out(size, '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), size, nullptr,
                        nullptr);
    return out;
}

BOOL WINAPI privateUserProfile(HANDLE, LPSTR buffer, LPDWORD size) {
    const DWORD required = static_cast<DWORD>(profile.size() + 1);
    if (!size) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    if (!buffer || *size < required) {
        *size = required;
        SetLastError(ERROR_INSUFFICIENT_BUFFER);
        return FALSE;
    }
    memcpy(buffer, profile.c_str(), required);
    *size = required;
    log("profile_redirect=" + profile);
    return TRUE;
}

FARPROC WINAPI privateGetProc(HMODULE module, LPCSTR name) {
    if (isolated && reinterpret_cast<std::uintptr_t>(name) > 0xFFFF &&
        strcmp(name, "GetUserProfileDirectoryA") == 0) {
        FARPROC result;
        auto function = privateUserProfile;
        static_assert(sizeof(function) == sizeof(result));
        memcpy(&result, &function, sizeof(result));
        return result;
    }
    return isaac::input::resolve(module, name, originalGetProc(module, name));
}

// Test instances are started explicitly, never redirected into the user's main
// Steam game directory. Steam authentication itself is left unchanged.
bool __cdecl noSteamRelaunch(unsigned int) {
    return false;
}

bool replaceImport(const char* name, void* replacement) {
    const auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(image);
    const auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(image + dos->e_lfanew);
    auto imports = reinterpret_cast<const IMAGE_IMPORT_DESCRIPTOR*>(
        image + nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress);
    for (; imports->Name; ++imports) {
        auto names = reinterpret_cast<const IMAGE_THUNK_DATA*>(image + imports->OriginalFirstThunk);
        auto addresses = reinterpret_cast<IMAGE_THUNK_DATA*>(image + imports->FirstThunk);
        for (; names->u1.AddressOfData; ++names, ++addresses) {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal))
                continue;
            const auto entry =
                reinterpret_cast<const IMAGE_IMPORT_BY_NAME*>(image + names->u1.AddressOfData);
            if (strcmp(reinterpret_cast<const char*>(entry->Name), name) != 0)
                continue;
            DWORD before;
            if (!VirtualProtect(&addresses->u1.Function, sizeof(void*), PAGE_READWRITE, &before))
                return false;
            addresses->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
            DWORD ignored;
            VirtualProtect(&addresses->u1.Function, sizeof(void*), before, &ignored);
            return true;
        }
    }
    return false;
}

template <class T> bool read(std::uintptr_t address, T& value) {
    SIZE_T count = 0;
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(address), &value,
                             sizeof(T), &count) &&
           count == sizeof(T);
}

// RVAs belong to the J460 build, verified by layout and entry-point signatures;
// no pointer offsets from another game version are assumed to be compatible.
constexpr std::uintptr_t gamePointerRva = 0x871678;
constexpr std::uintptr_t roomOffset = 0x18300;
constexpr std::uintptr_t playersOffset = 0x1baa8;
constexpr std::uintptr_t frameOffset = 0x264f8;

using LuaFn = int(__cdecl*)(lua_State*);
struct LuaAPI {
    void(__cdecl* createTable)(lua_State*, int, int) = nullptr;
    void(__cdecl* pushClosure)(lua_State*, LuaFn, int) = nullptr;
    void(__cdecl* setField)(lua_State*, int, const char*) = nullptr;
    const char*(__cdecl* pushString)(lua_State*, const char*) = nullptr;
    long long(__cdecl* checkInteger)(lua_State*, int) = nullptr;
    void(__cdecl* pushBoolean)(lua_State*, int) = nullptr;
    void(__cdecl* pushValue)(lua_State*, int) = nullptr;
    int(__cdecl* pcall)(lua_State*, int, int, int, std::intptr_t, void*) = nullptr;
} lua;

template <class T> T& field(std::uintptr_t base, std::size_t offset) {
    return *reinterpret_cast<T*>(base + offset);
}
template <class T> T engine(std::uintptr_t rva) {
    return reinterpret_cast<T>(image + rva);
}
using NativeRoomCall = void(__attribute__((thiscall)) *)(void*);
using NativeRoomInit = void(__attribute__((thiscall)) *)(void*, void*, void*);
using NativeGetDesc = void*(__attribute__((thiscall)) *)(void*, int, int);

std::uintptr_t backgroundRoom = 0;
int backgroundIndex = -1;
int roomSteps = 0;
bool roomScopeActive = false;
NativeRoomCall originalRoomUpdate = nullptr;
NativeRoomCall originalGameRender = nullptr;
using NativeHalfUpdate = void(__cdecl*)();
NativeHalfUpdate originalHalfUpdate = nullptr;
unsigned foregroundNativeUpdates = 0, backgroundNativeUpdates = 0;
unsigned foregroundHalfUpdates = 0, backgroundHalfUpdates = 0;
void tickBackground(std::uintptr_t game);

void __attribute__((fastcall)) updateForeground(void* room, void*) {
    if (isaac::rooms::update(room, originalRoomUpdate))
        return;
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    if (!backgroundRoom || roomScopeActive ||
        reinterpret_cast<std::uintptr_t>(room) == backgroundRoom) {
        originalRoomUpdate(room);
        return;
    }
    const auto begin = field<std::uintptr_t>(game, playersOffset);
    const auto end = field<std::uintptr_t>(game, playersOffset + 4);
    field<std::uintptr_t>(game, playersOffset + 4) = begin + 4;
    originalRoomUpdate(room);
    field<std::uintptr_t>(game, playersOffset + 4) = end;
    ++foregroundNativeUpdates;
    tickBackground(game);
}

// The eight independent EntityList backing arrays are constructed by the game.
// Remove references without destroying the entity, then let native Add register
// it in the destination's persistent, update, rendering and query structures.
void movePlayer(std::uintptr_t player, std::uintptr_t from, std::uintptr_t to) {
    for (std::size_t offset = 0x20; offset <= 0x90; offset += 0x10) {
        const auto list = from + 0x1218 + offset;
        auto data = reinterpret_cast<std::uintptr_t*>(field<std::uintptr_t>(list, 4));
        auto& size = field<unsigned>(list, 12);
        for (unsigned i = 0; i < size;) {
            if (data[i] != player) {
                ++i;
                continue;
            }
            memmove(data + i, data + i + 1, (size - i - 1) * sizeof(*data));
            --size;
        }
    }
    using InvalidateQuery = void(__attribute__((thiscall))*)(void*, unsigned, unsigned, unsigned);
    engine<InvalidateQuery>(0x1b570)(reinterpret_cast<void*>(from + 0x1218), 1, 0, 0);
    field<bool>(player, 0x170) = false;
    field<unsigned>(player, 0x20) = field<unsigned>(to, 0x1214)++;
    using Add = void(__attribute__((thiscall))*)(void*, void*);
    engine<Add>(0x18500)(reinterpret_cast<void*>(to + 0x1218), reinterpret_cast<void*>(player));
}

// Internal experiment only: scoped engine view, not a complete room scheduler.
// Never copy ownership-bearing engine objects or pass MinGW STL to MSVC code.
struct RoomScope {
    std::uintptr_t game;
    std::uintptr_t originalRoom;
    int originalIndex, originalDimension;
    std::array<std::uintptr_t, 3> players;
    explicit RoomScope(std::uintptr_t g) : game(g) {
        originalRoom = field<std::uintptr_t>(g, roomOffset);
        originalIndex = field<int>(g, 0x18304);
        originalDimension = field<int>(g, 0x1830c);
        memcpy(players.data(), reinterpret_cast<void*>(g + playersOffset), sizeof(players));
        field<std::uintptr_t>(g, roomOffset) = backgroundRoom;
        field<int>(g, 0x18304) = backgroundIndex;
        field<int>(g, 0x1830c) = 0;
        // Keep the game's own backing allocation. This experiment requires two
        // ordinary players and exposes only player two during background work.
        field<std::uintptr_t>(g, playersOffset) = players[0] + 4;
        field<std::uintptr_t>(g, playersOffset + 4) = players[0] + 8;
        roomScopeActive = true;
    }
    ~RoomScope() {
        if (field<std::uintptr_t>(game, playersOffset) != players[0] + 4 ||
            field<std::uintptr_t>(game, playersOffset + 8) != players[2]) {
            log("room_scope=FAIL player_vector_reallocated");
            TerminateProcess(GetCurrentProcess(), 91);
        }
        memcpy(reinterpret_cast<void*>(game + playersOffset), players.data(), sizeof(players));
        field<std::uintptr_t>(game, roomOffset) = originalRoom;
        field<int>(game, 0x18304) = originalIndex;
        field<int>(game, 0x1830c) = originalDimension;
        roomScopeActive = false;
    }
    RoomScope(const RoomScope&) = delete;
};

void __attribute__((fastcall)) renderLocalRoom(void* game, void*) {
    isaac::input::ViewScope inputView(isaac::runtime::localViewSlot());
    isaac::runtime::present();
    isaac::frontend::prepareView();
    if (isaac::rooms::render(game, originalGameRender, isaac::runtime::localViewSlot())) {
        isaac::frontend::render();
        return;
    }
    if (backgroundRoom && !roomScopeActive && isaac::runtime::localViewSlot() == 1) {
        RoomScope context(reinterpret_cast<std::uintptr_t>(game));
        originalGameRender(game);
    } else
        originalGameRender(game);
    isaac::frontend::render();
}

void restoreRoomPositions(std::uintptr_t room) {
    // The manager restores interpolated positions only for its visible room
    // (J460 VA 0x9551d8). Apply the same operation before background physics.
    const auto list = room + 0x1218 + 0x40;
    const auto data = field<std::uintptr_t>(list, 4);
    for (unsigned i = 0; i < field<unsigned>(list, 12); ++i) {
        auto entity = field<std::uintptr_t>(data, i * 4);
        if (field<bool>(entity, 0x175)) {
            field<float>(entity, 0x33c) = field<float>(entity, 0x344);
            field<float>(entity, 0x340) = field<float>(entity, 0x348);
            field<bool>(entity, 0x175) = false;
        }
    }
}

void restoreForegroundPositions() {
    restoreRoomPositions(
        field<std::uintptr_t>(field<std::uintptr_t>(image, gamePointerRva), roomOffset));
}

void tickBackground(std::uintptr_t game) {
    RoomScope context(game);
    restoreRoomPositions(backgroundRoom);
    originalRoomUpdate(reinterpret_cast<void*>(backgroundRoom));
    ++backgroundNativeUpdates;
}

void __cdecl updateHalfFrames() {
    if (!isaac::runtime::halfAllowed())
        return;
    isaac::runtime::halfStarted();
    if (isaac::rooms::half(originalHalfUpdate)) {
        isaac::runtime::halfCompleted();
        return;
    }
    originalHalfUpdate();
    if (!backgroundRoom || roomScopeActive) {
        isaac::runtime::halfCompleted();
        return;
    }
    ++foregroundHalfUpdates;
    {
        RoomScope context(field<std::uintptr_t>(image, gamePointerRva));
        // This experiment disallows room transitions. Production needs a
        // separate transition context before this can schedule arbitrary rooms.
        originalHalfUpdate();
        ++backgroundHalfUpdates;
    }
    isaac::runtime::halfCompleted();
}

void describeRoom(const char* name, std::uintptr_t room) {
    auto list = room + 0x1218 + 0x20;
    auto data = field<std::uintptr_t>(list, 4);
    auto count = field<unsigned>(list, 12);
    char line[256];
    snprintf(line, sizeof(line), "%s room=%08lx count=%u", name, static_cast<unsigned long>(room),
             count);
    log(line);
    if (count > 2000)
        return;
    for (unsigned i = 0; i < count && i < 30; ++i) {
        auto entity = field<std::uintptr_t>(data, i * 4);
        snprintf(line, sizeof(line), " entity=%08lx type=%u variant=%u",
                 static_cast<unsigned long>(entity), field<unsigned>(entity, 0x28),
                 field<unsigned>(entity, 0x2c));
        log(line);
    }
}

int createRoom(lua_State* L) {
    const int index = static_cast<int>(lua.checkInteger(L, 1));
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    if (backgroundRoom || roomScopeActive || index < 0 || index >= 169 ||
        field<int>(game, 0x18304) == index ||
        field<std::uintptr_t>(game, playersOffset + 4) -
                field<std::uintptr_t>(game, playersOffset) !=
            8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto desc = reinterpret_cast<std::uintptr_t>(
        engine<NativeGetDesc>(0x340bc0)(reinterpret_cast<void*>(game), index, 0));
    if (!desc || !field<std::uintptr_t>(desc, 0x10)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    log("room_create=BEGIN");
    roomSteps = 0;
    foregroundNativeUpdates = backgroundNativeUpdates = 0;
    foregroundHalfUpdates = backgroundHalfUpdates = 0;
    using Allocate = void*(__cdecl*)(std::size_t);
    backgroundRoom = reinterpret_cast<std::uintptr_t>(engine<Allocate>(0x60f4c0)(0x7898));
    if (!backgroundRoom) {
        lua.pushBoolean(L, false);
        return 1;
    }
    engine<NativeRoomCall>(0x3e9400)(reinterpret_cast<void*>(backgroundRoom));
    backgroundIndex = index;
    {
        RoomScope context(game);
        engine<NativeRoomInit>(0x3f2800)(reinterpret_cast<void*>(backgroundRoom),
                                         reinterpret_cast<void*>(field<std::uintptr_t>(desc, 0x10)),
                                         reinterpret_cast<void*>(desc));
        auto player = field<std::uintptr_t>(field<std::uintptr_t>(game, playersOffset), 0);
        movePlayer(player, context.originalRoom, backgroundRoom);
    }
    describeRoom("foreground_after_init", field<std::uintptr_t>(game, roomOffset));
    describeRoom("background_after_init", backgroundRoom);
    log("room_create=RETURNED");
    lua.pushBoolean(L, true);
    return 1;
}

int finishRooms(lua_State* L) {
    if (!backgroundRoom || roomScopeActive) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    auto foreground = field<std::uintptr_t>(game, roomOffset);
    auto player = field<std::uintptr_t>(field<std::uintptr_t>(game, playersOffset), 4);
    movePlayer(player, backgroundRoom, foreground);
    // Native destructor owns native container allocations; native sized delete
    // releases the object from the same allocator used during construction.
    engine<NativeRoomCall>(0x3e9ba0)(reinterpret_cast<void*>(backgroundRoom));
    using Delete = void(__cdecl*)(void*, std::size_t);
    engine<Delete>(0x6ef15c)(reinterpret_cast<void*>(backgroundRoom), 0x7898);
    backgroundRoom = 0;
    log("room_cleanup=RETURNED");
    lua.pushBoolean(L, true);
    return 1;
}

int traceCallback(lua_State* L) {
    const int who = static_cast<int>(lua.checkInteger(L, 1));
    static unsigned counts[3] = {};
    if (who < 1 || who > 2 || counts[who]++ >= 2)
        return 0;
    void* frames[48] = {};
    auto size = CaptureStackBackTrace(0, 48, frames, nullptr);
    std::string result = "player_callback_stack=" + std::to_string(who);
    for (unsigned i = 0; i < size; ++i) {
        auto pc = reinterpret_cast<std::uintptr_t>(frames[i]);
        if (pc >= image && pc < image + 0x92c000) {
            char address[24];
            snprintf(address, sizeof(address), " %08lx",
                     static_cast<unsigned long>(pc - image + 0x400000));
            result += address;
        }
    }
    log(result);
    return 0;
}

int withRoom(lua_State* L) {
    if (!backgroundRoom || roomScopeActive) {
        lua.pushBoolean(L, false);
        return 1;
    }
    int status;
    {
        RoomScope context(field<std::uintptr_t>(image, gamePointerRva));
        lua.pushValue(L, 1);
        status = lua.pcall(L, 0, 0, 0, 0, nullptr);
    }
    lua.pushBoolean(L, status == 0);
    return 1;
}

int stepRoom(lua_State* L) {
    if (!backgroundRoom || roomScopeActive) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (++roomSteps <= 3 || roomSteps % 60 == 0) {
        log("room_poll=" + std::to_string(roomSteps) +
            " foreground_native_updates=" + std::to_string(foregroundNativeUpdates) +
            " background_native_updates=" + std::to_string(backgroundNativeUpdates) +
            " foreground_half_updates=" + std::to_string(foregroundHalfUpdates) +
            " background_half_updates=" + std::to_string(backgroundHalfUpdates));
    }
    lua.pushBoolean(L, foregroundNativeUpdates == backgroundNativeUpdates &&
                           backgroundNativeUpdates > 0);
    return 1;
}

LONG CALLBACK recordException(EXCEPTION_POINTERS* exception) {
    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    char line[512];
    snprintf(line, sizeof(line),
             "native_exception=%08lx eip=%08lx ecx=%08lx edx=%08lx scope=%d image=%08lx rva=%08lx "
             "access=%lu address=%08lx",
             exception->ExceptionRecord->ExceptionCode, exception->ContextRecord->Eip,
             exception->ContextRecord->Ecx, exception->ContextRecord->Edx, roomScopeActive,
             static_cast<unsigned long>(image),
             exception->ContextRecord->Eip - static_cast<unsigned long>(image),
             static_cast<unsigned long>(exception->ExceptionRecord->ExceptionInformation[0]),
             static_cast<unsigned long>(exception->ExceptionRecord->ExceptionInformation[1]));
    log(line);
    std::string stack = "native_exception_stack=";
    for (unsigned i = 0; i < 48; ++i) {
        DWORD address = 0;
        if (!read(exception->ContextRecord->Esp + 4 * i, address))
            break;
        if (address >= image && address < image + 0x92c000) {
            snprintf(line, sizeof(line), " %08lx", address - static_cast<unsigned long>(image));
            stack += line;
        }
    }
    log(stack);
    return EXCEPTION_CONTINUE_SEARCH;
}

int audit(lua_State* L) {
    std::uintptr_t game = 0, room = 0, begin = 0, end = 0;
    int stage = 0, index = 0, gameFrame = 0, enteredFrame = 0;
    bool valid = initialized && read(image + gamePointerRva, game) && game &&
                 read(game + roomOffset, room) && room && read(game, stage) &&
                 read(game + 0x18304, index) && read(game + frameOffset, gameFrame) &&
                 read(room + 0x11f0, enteredFrame) && read(game + playersOffset, begin) &&
                 read(game + playersOffset + 4, end) && end >= begin && end - begin <= 32;
    int roomFrame = gameFrame - enteredFrame;
    int players = static_cast<int>((end - begin) / 4);
    if (valid)
        valid = stage == lua.checkInteger(L, 1) && index == lua.checkInteger(L, 2) &&
                roomFrame == lua.checkInteger(L, 3) && players == lua.checkInteger(L, 4);
    char line[384];
    snprintf(line, sizeof(line),
             "audit=%s game=%08lx room=%08lx stage=%d index=%d room_frame=%d players=%d",
             valid ? "PASS" : "FAIL", static_cast<unsigned long>(game),
             static_cast<unsigned long>(room), stage, index, roomFrame, players);
    log(line);
    lua.pushBoolean(L, valid);
    return 1;
}
} // namespace

extern "C" __declspec(dllexport) DWORD WINAPI IsaacLanBootstrap(void*) {
    wchar_t env[1024] = {}, executable[1024] = {};
    DWORD size = GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", env, 1024);
    const auto length = GetModuleFileNameW(nullptr, executable, 1024);
    if (!length || length >= 1024)
        return 11;
    const auto directory = std::filesystem::path(executable).parent_path();
    std::ifstream marker(directory / L".isaac-lan-install");
    std::string identity;
    std::getline(marker, identity);
    const bool installed = identity == "IsaacLAN/1";
    if (size >= 1024 && !installed)
        return 10;
    const std::wstring expected =
        size && size < 1024 ? std::wstring(env) + L"\\game\\isaac-ng.exe" : std::wstring{};
    const bool matchesLab = !expected.empty() && _wcsicmp(executable, expected.c_str()) == 0;
    const bool markedLab =
        matchesLab && GetFileAttributesW((std::wstring(env) + L"\\.isaac-lan-lab").c_str()) !=
                          INVALID_FILE_ATTRIBUTES;
    const auto selected = isaac::bootstrap::profile(installed, size != 0, matchesLab, markedLab);
    if (selected == isaac::bootstrap::Profile::wrongPath)
        return 11;
    if (selected == isaac::bootstrap::Profile::missingMarker)
        return 12;
    isolated = selected == isaac::bootstrap::Profile::isolated;
    if (isolated) {
        root = env;
    } else {
        root = (directory / L"isaac-lan").wstring();
        std::error_code error;
        std::filesystem::create_directories(root, error);
        if (error)
            return 14;
        if (size) {
            SetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", nullptr);
            SetEnvironmentVariableW(L"ISAAC_LAN_LAB_READY", nullptr);
            SetEnvironmentVariableW(L"ISAAC_LAN_LAB_LOADER_READY", nullptr);
            log("startup_lab_environment=IGNORED foreign_executable");
        }
    }
    image = reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
    auto compatibilityError = isaac::build::checkFile(executable);
    if (compatibilityError.empty())
        compatibilityError = isaac::build::checkMemory(image);
    if (!compatibilityError.empty()) {
        log("game_compatibility=FAILED " + compatibilityError);
        if (!isolated)
            MessageBoxA(nullptr, compatibilityError.c_str(), "Isaac LAN - game compatibility",
                        MB_OK | MB_ICONERROR);
        return 13;
    }
    log("game_compatibility=PASS build=" + std::string(isaac::build::version));
    isaac::input::install(image, log, installed);
    if (isolated) {
        profile = utf8(root + L"\\profile");
        if (profile.size() > 800 || profile.find_first_of("\r\n") != std::string::npos)
            return 14;
    }
    if (!replaceImport("GetProcAddress", reinterpret_cast<void*>(privateGetProc)))
        return 15;
    if (isolated)
        replaceImport("SteamAPI_RestartAppIfNecessary", reinterpret_cast<void*>(noSteamRelaunch));
    if (!replaceImport("GetActiveWindow", reinterpret_cast<void*>(localActiveWindow)))
        return 19;
    initialized = true;
    AddVectoredExceptionHandler(1, recordException);
    if (MH_Initialize() != MH_OK ||
        MH_CreateHook(reinterpret_cast<void*>(image + 0x402980),
                      reinterpret_cast<void*>(updateForeground),
                      reinterpret_cast<void**>(&originalRoomUpdate)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(image + 0x402980)) != MH_OK)
        return 16;
    if (MH_CreateHook(reinterpret_cast<void*>(image + 0x2fd3f0),
                      reinterpret_cast<void*>(updateHalfFrames),
                      reinterpret_cast<void**>(&originalHalfUpdate)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(image + 0x2fd3f0)) != MH_OK)
        return 17;
    log(std::string("bootstrap=PASS version=1.9.7.17.J460 isolation=") +
        (isolated ? "profile_redirect" : "installed"));
    log(std::string("installation_mode=") + (installed ? "installed" : "lab"));
    if (!isaac::runtime::install(image, log, updateHalfFrames, restoreForegroundPositions))
        return 18;
    if (!isaac::rooms::install(image, log))
        return 21;
    if (!isaac::audio::install(image))
        return 23;
    if (!isaac::presentation::install(image))
        return 24;
    if (!isaac::rewind::install(image))
        return 25;
    if (!isaac::frontend::install(image, root, log, luaopen_isaac_lan_probe, installed))
        return 22;
    if (MH_CreateHook(reinterpret_cast<void*>(image + 0x2fbc10),
                      reinterpret_cast<void*>(renderLocalRoom),
                      reinterpret_cast<void**>(&originalGameRender)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(image + 0x2fbc10)) != MH_OK)
        return 20;
    if (isolated) {
        wchar_t eventName[128]{};
        if (GetEnvironmentVariableW(L"ISAAC_LAN_LAB_READY", eventName, 128)) {
            const auto ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, eventName);
            if (ready) {
                SetEvent(ready);
                CloseHandle(ready);
            }
        }
    }
    return 0;
}

extern "C" __declspec(dllexport) int __cdecl luaopen_isaac_lan_probe(lua_State* L) {
    if (!initialized)
        return 0;
    HMODULE module = GetModuleHandleW(L"Lua5.3.3r.dll");
    if (!module)
        return 0;
#define LUA_IMPORT(field, name)                                                                    \
    do {                                                                                           \
        auto p = originalGetProc(module, name);                                                    \
        static_assert(sizeof(p) == sizeof(lua.field));                                             \
        memcpy(&lua.field, &p, sizeof(p));                                                         \
        if (!lua.field)                                                                            \
            return 0;                                                                              \
    } while (false)
    LUA_IMPORT(createTable, "lua_createtable");
    LUA_IMPORT(pushClosure, "lua_pushcclosure");
    LUA_IMPORT(setField, "lua_setfield");
    LUA_IMPORT(pushString, "lua_pushstring");
    LUA_IMPORT(checkInteger, "luaL_checkinteger");
    LUA_IMPORT(pushBoolean, "lua_pushboolean");
    LUA_IMPORT(pushValue, "lua_pushvalue");
    LUA_IMPORT(pcall, "lua_pcallk");
#undef LUA_IMPORT
    lua.createTable(L, 0, 1);
    lua.pushClosure(L, audit, 0);
    lua.setField(L, -2, "audit");
    lua.pushClosure(L, createRoom, 0);
    lua.setField(L, -2, "create_room");
    lua.pushClosure(L, withRoom, 0);
    lua.setField(L, -2, "with_room");
    lua.pushClosure(L, stepRoom, 0);
    lua.setField(L, -2, "step_room");
    lua.pushClosure(L, finishRooms, 0);
    lua.setField(L, -2, "finish_rooms");
    lua.pushClosure(L, traceCallback, 0);
    lua.setField(L, -2, "trace_callback");
    if (!isaac::runtime::bind(L, module))
        return 0;
    if (!isaac::rooms::bind(L, module))
        return 0;
    if (!isaac::audio::bind(L, module))
        return 0;
    if (!isaac::presentation::bind(L, module))
        return 0;
    if (!isaac::rewind::bind(L, module))
        return 0;
    if (!isaac::input::bind(L, module))
        return 0;
    return 1;
}

BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) {
    return TRUE;
}

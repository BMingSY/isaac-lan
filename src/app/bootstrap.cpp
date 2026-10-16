#include "engine/lua_api.h"
// J460 native adapter. Lab launches retain explicit profile isolation; ordinary
// launches require the installer marker, J460 layout and compatible entry points.
#include <windows.h>
#include <MinHook.h>
#include <shlobj.h>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <filesystem>
#include <fstream>
#include "runtime/session.h"
#include "engine/audio.h"
#include "engine/presentation.h"
#include "engine/rewind.h"
#include "engine/rooms.h"
#include "engine/input.h"
#include "engine/generated_items.h"
#include "engine/frontend.h"
#include "engine/build.h"
#include "core/bootstrap_profile.h"
#include "diagnostics/runtime_log.h"
#include "diagnostics/performance.h"
#include "diagnostics/crash_signal.h"
#include "app/configuration.h"

extern "C" __declspec(dllexport) int __cdecl luaopen_isaac_lan_probe(lua_State* L);

#include "engine/bootstrap.h"
#include "diagnostics/native_exceptions.h"

namespace {
static_assert(sizeof(void*) == 4);
std::wstring root;
std::string profile;
std::uintptr_t image = 0;
bool initialized = false;
bool isolated = true;
isaac::configuration::Settings settings;
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
    isaac::logging::write(line);
}

void observeNativeLog(const char* name) {
    const auto error = GetLastError();
    try {
        if (name) {
            const auto length = MultiByteToWideChar(CP_ACP, 0, name, -1, nullptr, 0);
            if (length > 0) {
                std::wstring path(length, L'\0');
                MultiByteToWideChar(CP_ACP, 0, name, -1, path.data(), length);
                isaac::logging::nativeFileOpened(path.c_str());
            }
        }
    } catch (...) {
        // Observing a log path must never alter a successful native file open.
    }
    SetLastError(error);
}
HANDLE WINAPI nativeOpenFile(LPCSTR name, DWORD access, DWORD sharing,
                             LPSECURITY_ATTRIBUTES attributes, DWORD creation, DWORD flags,
                             HANDLE templateFile) {
    const auto handle =
        CreateFileA(name, access, sharing, attributes, creation, flags, templateFile);
    if (handle != INVALID_HANDLE_VALUE && (access & (GENERIC_WRITE | FILE_APPEND_DATA)))
        observeNativeLog(name);
    return handle;
}
using NativeFopen = void*(__cdecl*)(const char*, const char*);
using NativeFiopen = void*(__cdecl*)(const char*, int, int);
NativeFopen originalFopen;
NativeFiopen originalFiopen;
void* __cdecl nativeFopen(const char* name, const char* mode) {
    const auto file = originalFopen(name, mode);
    if (file && mode && std::strpbrk(mode, "wa+"))
        observeNativeLog(name);
    return file;
}
void* __cdecl nativeFiopen(const char* name, int mode, int protection) {
    const auto file = originalFiopen(name, mode, protection);
    if (file && (mode & (2 | 8)))
        observeNativeLog(name);
    return file;
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

bool replaceImport(const char* name, void* replacement, void** original = nullptr) {
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
            if (original)
                *original = reinterpret_cast<void*>(addresses->u1.Function);
            addresses->u1.Function = reinterpret_cast<ULONG_PTR>(replacement);
            DWORD ignored;
            VirtualProtect(&addresses->u1.Function, sizeof(void*), before, &ignored);
            return true;
        }
    }
    return false;
}

isaac::lua::API lua{};
int diagnosticsBegin(lua_State* L) {
    const auto seed = lua.checkString(L, 1, nullptr);
    const auto role = lua.checkString(L, 2, nullptr);
    const auto continued = lua.checkInteger(L, 3) != 0;
    const bool ok = isaac::logging::beginRun(seed, role, continued);
    if (ok)
        isaac::diagnostics::beginRun();
    lua.pushBoolean(L, ok);
    return 1;
}
int diagnosticsEnd(lua_State*) {
    isaac::diagnostics::endRun();
    isaac::logging::endRun();
    return 0;
}
int diagnosticsEnabled(lua_State* L) {
    lua.pushBoolean(L, isaac::diagnostics::enabled());
    return 1;
}
int diagnosticsSample(lua_State* L) {
    isaac::diagnostics::sample(lua.checkString(L, 1, nullptr), lua.checkNumber(L, 2));
    return 0;
}
int diagnosticsCounter(lua_State* L) {
    const auto name = lua.checkString(L, 1, nullptr);
    const auto value = lua.checkInteger(L, 2);
    if (value >= 0)
        isaac::diagnostics::counter(name, static_cast<std::uint64_t>(value));
    return 0;
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
    wchar_t documents[MAX_PATH]{};
    std::filesystem::path logDirectory;
    if (isolated)
        logDirectory =
            std::filesystem::path(env) / L"profile/Documents/My Games/Binding of Isaac Repentance+";
    else if (SUCCEEDED(
                 SHGetFolderPathW(nullptr, CSIDL_PERSONAL, nullptr, SHGFP_TYPE_CURRENT, documents)))
        logDirectory = std::filesystem::path(documents) / L"My Games/Binding of Isaac Repentance+";
    else
        return 14;
    const auto config = isaac::configuration::load(directory / L"isaac-lan/config.ini");
    settings = config.settings;
    isaac::runtime::configureInput(settings.inputHz);
    isaac::logging::configure(settings.logLevel);
    isaac::diagnostics::configure(settings);
    if (!isaac::logging::initialize(logDirectory))
        return 14;
    for (const auto& warning : config.warnings)
        log("config_warning=" + warning);
    log("network_input_hz=" + std::to_string(settings.inputHz));
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
    if (!replaceImport("CreateFileA", reinterpret_cast<void*>(nativeOpenFile)))
        return 15;
    // Native loggers use both CRT stdio and C++ streams. Preserve the game's
    // own CRT file objects; observe their successful opens without borrowing
    // or closing them from this DLL's different runtime.
    if (!replaceImport("fopen", reinterpret_cast<void*>(nativeFopen),
                       reinterpret_cast<void**>(&originalFopen)) ||
        !replaceImport("?_Fiopen@std@@YAPAU_iobuf@@PBDHH@Z", reinterpret_cast<void*>(nativeFiopen),
                       reinterpret_cast<void**>(&originalFiopen)))
        return 15;
    if (isolated)
        replaceImport("SteamAPI_RestartAppIfNecessary", reinterpret_cast<void*>(noSteamRelaunch));
    if (!replaceImport("GetActiveWindow", reinterpret_cast<void*>(localActiveWindow)))
        return 19;
    initialized = true;
    isaac::diagnostics::observeExceptions(image, isaac::engine::bootstrap::scopeActive);
    if (MH_Initialize() != MH_OK)
        return 16;
    if (const auto error = isaac::engine::bootstrap::installUpdates(image, log))
        return error;
    log(std::string("bootstrap=PASS version=1.9.7.17.J460 isolation=") +
        (isolated ? "profile_redirect" : "installed"));
    log(std::string("installation_mode=") + (installed ? "installed" : "lab"));
    if (!isaac::runtime::install(image, log, isaac::engine::bootstrap::halfUpdate,
                                 isaac::engine::bootstrap::restorePositions))
        return 18;
    if (!isaac::generated_items::install(image))
        return 27;
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
    if (const auto error = isaac::engine::bootstrap::installRendering())
        return error;
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
    if (!lua.load(module,
                  {isaac::lua::Symbol::createTable, isaac::lua::Symbol::pushClosure,
                   isaac::lua::Symbol::setField, isaac::lua::Symbol::pushString,
                   isaac::lua::Symbol::checkInteger, isaac::lua::Symbol::checkString,
                   isaac::lua::Symbol::checkNumber, isaac::lua::Symbol::pushBoolean,
                   isaac::lua::Symbol::pushValue, isaac::lua::Symbol::pcall},
                  originalGetProc))
        return 0;
    lua.createTable(L, 0, 1);
    for (const auto& [name, fn] : std::array<std::pair<const char*, isaac::lua::Function>, 5>{
             {{"diagnostics_begin", diagnosticsBegin},
              {"diagnostics_end", diagnosticsEnd},
              {"diagnostics_enabled", diagnosticsEnabled},
              {"diagnostics_sample", diagnosticsSample},
              {"diagnostics_counter", diagnosticsCounter}}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    }
    if (!isaac::engine::bootstrap::bind(L, module))
        return 0;
    if (!isaac::runtime::bind(L, module))
        return 0;
    if (!isaac::generated_items::bind(L, module))
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

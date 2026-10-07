// Automatic loader. The original multimedia API is forwarded unchanged.
// The engine adapter is initialized after Windows releases the loader lock,
// before the game's executable entry point can discover profiles or load Lua.
#include <windows.h>
#include <cstdint>
#include <cwchar>

extern "C" {
FARPROC lan_winmm_functions[193]{};
#define WINMM_EXPORT(index, ordinal, name) \
    __attribute__((naked)) void lan_winmm_##index() { __asm__ volatile("jmp *_lan_winmm_functions+" #index "*4"); }
#include "loader_exports.inc"
#undef WINMM_EXPORT
}
namespace {
void* entry = nullptr;
WORD entryBytes = 0;
wchar_t extension[MAX_PATH]{};
void restoreEntry() {
    DWORD old;
    if(!VirtualProtect(entry,2,PAGE_EXECUTE_READWRITE,&old)) TerminateProcess(GetCurrentProcess(),90);
    __atomic_exchange_n(static_cast<WORD*>(entry),entryBytes,__ATOMIC_SEQ_CST);
    FlushInstructionCache(GetCurrentProcess(),entry,2);
    DWORD ignored; VirtualProtect(entry,2,old,&ignored);
}
DWORD WINAPI initialize(void*) {
    const auto module=LoadLibraryW(extension);
    using Bootstrap=DWORD(WINAPI*)(void*);
    Bootstrap bootstrap=nullptr;
    if(module) { auto proc=GetProcAddress(module,"IsaacLanBootstrap"); memcpy(&bootstrap,&proc,sizeof(proc)); }
    const DWORD result=bootstrap?bootstrap(nullptr):100;
    if(result) {
        wchar_t message[256];
        swprintf(message,256,L"Isaac LAN could not initialize (code %lu). The game will close.\nPlease check the installed game and extension versions.",result);
        MessageBoxW(nullptr,message,L"Isaac LAN",MB_OK|MB_ICONERROR);
        TerminateProcess(GetCurrentProcess(),result);
        return result;
    }
    restoreEntry();
    // Marked lab runner waits for both initialization and entry restoration;
    // its independent pre-entry isolation gate must not race this worker.
    wchar_t eventName[128]{};
    if(GetEnvironmentVariableW(L"ISAAC_LAN_LAB_LOADER_READY",eventName,128)) {
        const auto ready=OpenEventW(EVENT_MODIFY_STATE,FALSE,eventName);
        if(ready) { SetEvent(ready);CloseHandle(ready); }
    }
    return 0;
}
bool forwardExports() {
    wchar_t path[MAX_PATH]{};
    if(!GetSystemDirectoryW(path,MAX_PATH) || wcslen(path)+11>=MAX_PATH) return false;
    wcscat(path,L"\\winmm.dll");
    const auto system=LoadLibraryW(path);
    if(!system) return false;
#define WINMM_EXPORT(index, ordinal, name) \
    lan_winmm_functions[index]=GetProcAddress(system, *(name)?(name):MAKEINTRESOURCEA(ordinal)); \
    if(!lan_winmm_functions[index]) return false;
#include "loader_exports.inc"
#undef WINMM_EXPORT
    return true;
}
bool gateEntry() {
    wchar_t executable[MAX_PATH]{};
    if(!GetModuleFileNameW(nullptr,executable,MAX_PATH)) return false;
    const auto filename=wcsrchr(executable,L'\\');
    if(!filename || _wcsicmp(filename+1,L"isaac-ng.exe")) return true;
    const auto length=static_cast<std::size_t>(filename-executable)+1;
    if(length+20>=MAX_PATH) return false;
    wcsncpy(extension,executable,length);wcscat(extension,L"isaac_lan_probe.dll");
    const auto base=reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
    const auto dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto nt=reinterpret_cast<const IMAGE_NT_HEADERS*>(base+dos->e_lfanew);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || nt->Signature!=IMAGE_NT_SIGNATURE || nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_I386) return false;
    entry=reinterpret_cast<void*>(base+nt->OptionalHeader.AddressOfEntryPoint);
    memcpy(&entryBytes,entry,2);
    DWORD old;
    if(!VirtualProtect(entry,2,PAGE_EXECUTE_READWRITE,&old)) return false;
    __atomic_exchange_n(static_cast<WORD*>(entry),static_cast<WORD>(0xfeeb),__ATOMIC_SEQ_CST);
    FlushInstructionCache(GetCurrentProcess(),entry,2);
    DWORD ignored;VirtualProtect(entry,2,old,&ignored);
    const auto worker=CreateThread(nullptr,0,initialize,nullptr,0,nullptr);
    if(!worker) { restoreEntry();return false; }
    CloseHandle(worker);return true;
}
}
BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason!=DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(instance);
    return forwardExports() && gateEntry();
}

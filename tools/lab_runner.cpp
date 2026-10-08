// Internal test runner; injects only into the child process it just created.
#include <windows.h>
#include <tlhelp32.h>
#include <cstdio>
#include <string>
#include <vector>

namespace {
struct EntryGate {
    void* pointer = nullptr;
    WORD original = 0;
};
bool restoreEntry(PROCESS_INFORMATION& child, const EntryGate& gate) {
    DWORD protection, ignored;
    SIZE_T written = 0;
    if (!VirtualProtectEx(child.hProcess, gate.pointer, 2, PAGE_EXECUTE_READWRITE, &protection))
        return false;
    const bool restored =
        WriteProcessMemory(child.hProcess, gate.pointer, &gate.original, 2, &written) &&
        written == 2;
    FlushInstructionCache(child.hProcess, gate.pointer, 2);
    VirtualProtectEx(child.hProcess, gate.pointer, 2, protection, &ignored);
    return restored;
}
bool parkAtEntry(PROCESS_INFORMATION& child, EntryGate& gate) {
    // Let Windows finish loader initialization, but stop before the executable's
    // entry point. No game initialization (including save-path discovery) runs.
    CONTEXT context{};
    context.ContextFlags = CONTEXT_INTEGER;
    if (!GetThreadContext(child.hThread, &context))
        return false;
    DWORD base = 0;
    SIZE_T read = 0;
    if (!ReadProcessMemory(child.hProcess, reinterpret_cast<void*>(context.Ebx + 8), &base, 4,
                           &read) ||
        read != 4)
        return false;
    unsigned char headers[4096];
    if (!ReadProcessMemory(child.hProcess, reinterpret_cast<void*>(base), headers, sizeof(headers),
                           &read))
        return false;
    auto dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(headers);
    if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew < 0 || dos->e_lfanew > 3000)
        return false;
    auto nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(headers + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE || nt->FileHeader.Machine != IMAGE_FILE_MACHINE_I386)
        return false;
    void* entry = reinterpret_cast<void*>(base + nt->OptionalHeader.AddressOfEntryPoint);
    unsigned char original[2], loop[2] = {0xEB, 0xFE};
    DWORD protection;
    if (!ReadProcessMemory(child.hProcess, entry, original, 2, &read) || read != 2 ||
        !VirtualProtectEx(child.hProcess, entry, 2, PAGE_EXECUTE_READWRITE, &protection))
        return false;
    gate.pointer = entry;
    memcpy(&gate.original, original, 2);
    if (!WriteProcessMemory(child.hProcess, entry, loop, 2, &read) || read != 2)
        return false;
    FlushInstructionCache(child.hProcess, entry, 2);
    ResumeThread(child.hThread);
    bool parked = false;
    for (int attempt = 0; attempt < 1000; ++attempt) {
        Sleep(10);
        if (WaitForSingleObject(child.hProcess, 0) == WAIT_OBJECT_0)
            break;
        if (SuspendThread(child.hThread) == static_cast<DWORD>(-1))
            break;
        context = {};
        context.ContextFlags = CONTEXT_CONTROL;
        if (GetThreadContext(child.hThread, &context) &&
            context.Eip == reinterpret_cast<DWORD>(entry)) {
            parked = true;
            break;
        }
        ResumeThread(child.hThread);
    }
    if (!parked)
        return false;
    bool restored = WriteProcessMemory(child.hProcess, entry, original, 2, &read) && read == 2;
    FlushInstructionCache(child.hProcess, entry, 2);
    DWORD ignored;
    VirtualProtectEx(child.hProcess, entry, 2, protection, &ignored);
    return restored;
}

DWORD remoteCall(HANDLE process, LPTHREAD_START_ROUTINE function, void* argument) {
    HANDLE thread = CreateRemoteThread(process, nullptr, 0, function, argument, 0, nullptr);
    if (!thread)
        return 0xFFFFFFFF;
    DWORD wait = WaitForSingleObject(thread, 15000), result = 0xFFFFFFFF;
    if (wait == WAIT_OBJECT_0)
        GetExitCodeThread(thread, &result);
    CloseHandle(thread);
    return result;
}
} // namespace

int wmain(int argc, wchar_t** argv) {
    if (argc != 2 && argc != 3) {
        fwprintf(stderr, L"Usage: isaac_lan_lab.exe <marked isolated directory> [--automatic]\n");
        return 1;
    }
    const bool automatic = argc == 3 && !wcscmp(argv[2], L"--automatic");
    if (argc == 3 && !automatic)
        return 1;
    wchar_t full[1024];
    if (!GetFullPathNameW(argv[1], 1024, full, nullptr))
        return 2;
    std::wstring root = full;
    if (GetFileAttributesW((root + L"\\.isaac-lan-lab").c_str()) == INVALID_FILE_ATTRIBUTES)
        return 3;
    auto gameDir = root + L"\\game";
    auto exe = gameDir + L"\\isaac-ng.exe";
    auto dll = gameDir + L"\\isaac_lan_probe.dll";
    HMODULE local = LoadLibraryExW(dll.c_str(), nullptr, DONT_RESOLVE_DLL_REFERENCES);
    if (!local) {
        fprintf(stderr, "Cannot inspect probe DLL: %lu\n", GetLastError());
        return 4;
    }
    auto bootstrap = GetProcAddress(local, "IsaacLanBootstrap");
    if (!bootstrap) {
        FreeLibrary(local);
        return 5;
    }
    auto bootstrapRva = reinterpret_cast<DWORD>(bootstrap) - reinterpret_cast<DWORD>(local);
    FreeLibrary(local);
    SetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", root.c_str());
    SetEnvironmentVariableW(L"SteamAppId", L"250900");
    const auto readyName = L"Local\\IsaacLanLabReady-" + std::to_wstring(GetCurrentProcessId());
    HANDLE ready = CreateEventW(nullptr, TRUE, FALSE, readyName.c_str());
    if (!ready)
        return 6;
    SetEnvironmentVariableW(L"ISAAC_LAN_LAB_READY", automatic ? nullptr : readyName.c_str());
    SetEnvironmentVariableW(L"ISAAC_LAN_LAB_LOADER_READY", automatic ? readyName.c_str() : nullptr);
    std::wstring command = L"\"" + exe + L"\" --luadebug";
    std::vector<wchar_t> arguments(command.begin(), command.end());
    arguments.push_back(0);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION child{};
    const auto created =
        CreateProcessW(exe.c_str(), arguments.data(), nullptr, nullptr, FALSE, CREATE_SUSPENDED,
                       nullptr, gameDir.c_str(), &startup, &child);
    if (!created) {
        fprintf(stderr, "CreateProcess failed: %lu\n", GetLastError());
        return 6;
    }
    int result = 7;
    EntryGate gate;
    if (!parkAtEntry(child, gate)) {
        fprintf(stderr, "Could not establish pre-entry isolation gate: %lu\n", GetLastError());
        TerminateProcess(child.hProcess, result);
        CloseHandle(child.hThread);
        CloseHandle(child.hProcess);
        return result;
    }
    if (automatic) {
        // Never permit an uninitialized automatic loader to run the game's
        // profile discovery. The entry gate is released only after isolation.
        // The proxy may have saved our temporary EB FE entry bytes. Wait for
        // its own gate restoration, then restore the executable's true bytes
        // while the main thread is still suspended. Never race its worker.
        if (WaitForSingleObject(ready, 10000) == WAIT_OBJECT_0 && restoreEntry(child, gate)) {
            ResumeThread(child.hThread);
            printf("autoload_started=1 pid=%lu\n", child.dwProcessId);
            result = 0;
        } else {
            fprintf(stderr, "Automatic loader did not initialize before entry\n");
            PROCESS_MITIGATION_IMAGE_LOAD_POLICY policy{};
            if (GetProcessMitigationPolicy(child.hProcess, ProcessImageLoadPolicy, &policy,
                                           sizeof(policy)))
                fprintf(stderr, "Child DLL load policy flags=%lu\n", policy.Flags);
            if (GetProcessMitigationPolicy(GetCurrentProcess(), ProcessImageLoadPolicy, &policy,
                                           sizeof(policy)))
                fprintf(stderr, "Runner DLL load policy flags=%lu\n", policy.Flags);
            HANDLE modules = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32,
                                                      child.dwProcessId);
            if (modules != INVALID_HANDLE_VALUE) {
                MODULEENTRY32W item{};
                item.dwSize = sizeof(item);
                if (Module32FirstW(modules, &item))
                    do {
                        if (!_wcsicmp(item.szModule, L"winmm.dll") ||
                            !_wcsicmp(item.szModule, L"isaac_lan_probe.dll"))
                            fwprintf(stderr, L"Loaded module: %ls\n", item.szExePath);
                    } while (Module32NextW(modules, &item));
                CloseHandle(modules);
            }
            TerminateProcess(child.hProcess, result);
        }
        CloseHandle(ready);
        CloseHandle(child.hThread);
        CloseHandle(child.hProcess);
        return result;
    }
    SIZE_T bytes = (dll.size() + 1) * sizeof(wchar_t), written = 0;
    void* remote =
        VirtualAllocEx(child.hProcess, nullptr, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (remote && WriteProcessMemory(child.hProcess, remote, dll.c_str(), bytes, &written) &&
        written == bytes) {
        // Resolve the function in the child's kernel32, not by assuming ASLR bases.
        auto ownKernel = GetModuleHandleW(L"kernel32.dll");
        auto load = GetProcAddress(ownKernel, "LoadLibraryW");
        auto loadRva = reinterpret_cast<DWORD>(load) - reinterpret_cast<DWORD>(ownKernel);
        DWORD childKernel = 0;
        HANDLE modules =
            CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, child.dwProcessId);
        if (modules != INVALID_HANDLE_VALUE) {
            MODULEENTRY32W entry{};
            entry.dwSize = sizeof(entry);
            if (Module32FirstW(modules, &entry))
                do {
                    if (_wcsicmp(entry.szModule, L"kernel32.dll") == 0)
                        childKernel = reinterpret_cast<DWORD>(entry.modBaseAddr);
                } while (Module32NextW(modules, &entry));
            CloseHandle(modules);
        }
        if (childKernel) {
            DWORD module =
                remoteCall(child.hProcess,
                           reinterpret_cast<LPTHREAD_START_ROUTINE>(childKernel + loadRva), remote);
            if (module && module != 0xFFFFFFFF) {
                DWORD status = remoteCall(
                    child.hProcess, reinterpret_cast<LPTHREAD_START_ROUTINE>(module + bootstrapRva),
                    nullptr);
                printf("bootstrap_status=%lu pid=%lu\n", status, child.dwProcessId);
                if (status == 0) {
                    ResumeThread(child.hThread);
                    result = 0;
                }
            }
        }
    }
    if (result != 0)
        TerminateProcess(child.hProcess, result);
    if (remote)
        VirtualFreeEx(child.hProcess, remote, 0, MEM_RELEASE);
    CloseHandle(child.hThread);
    CloseHandle(child.hProcess);
    CloseHandle(ready);
    return result;
}

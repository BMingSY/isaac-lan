// Test-only observer. The marked lab's exception handler signals this process
// before allowing the game's own handler to proceed. No debugger/IFEO changes.
#include "diagnostics/crash_signal.h"
#include <dbghelp.h>
#include <cstdio>
#include <filesystem>

namespace {
std::filesystem::path fullPath(const wchar_t* source) {
    wchar_t buffer[32768]{};
    const auto size = GetFullPathNameW(source, 32768, buffer, nullptr);
    return size && size < 32768 ? std::filesystem::path(buffer) : std::filesystem::path{};
}
bool dump(HANDLE process, isaac::diagnostics::CrashSignal signal,
          const std::filesystem::path& output, unsigned ordinal) {
    const auto path =
        output / (std::to_wstring(signal.pid) + L"-" + std::to_wstring(ordinal) + L".dmp");
    // DbgHelp writes many small regions. Stage on a native Windows volume,
    // then copy the completed dump to an artifact path that may be on WSL.
    const auto temporary =
        std::filesystem::temp_directory_path() /
        (L"isaac-lan-heap-" + std::to_wstring(signal.pid) + L"-" +
         std::to_wstring(GetTickCount64()) + L"-" + std::to_wstring(ordinal) + L".dmp");
    const auto file = CreateFileW(temporary.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        std::printf("heap_dump_open=FAIL error=%lu\n", GetLastError());
        return false;
    }
    signal.exception.ExceptionRecord = nullptr; // A nested pointer belongs to the target.
    EXCEPTION_POINTERS pointers{&signal.exception, &signal.context};
    MINIDUMP_EXCEPTION_INFORMATION info{signal.thread, &pointers, FALSE};
    std::printf("heap_dump_begin pid=%lu code=%08lx eip=%08lx\n", signal.pid,
                signal.exception.ExceptionCode, signal.context.Eip);
    const bool ok = MiniDumpWriteDump(
        process, signal.pid, file,
        static_cast<MINIDUMP_TYPE>(MiniDumpWithFullMemory | MiniDumpWithHandleData |
                                   MiniDumpWithThreadInfo | MiniDumpWithUnloadedModules |
                                   MiniDumpIgnoreInaccessibleMemory | MiniDumpWithFullMemoryInfo),
        &info, nullptr, nullptr);
    const auto error = ok ? 0 : GetLastError();
    std::printf("heap_dump pid=%lu code=%08lx eip=%08lx result=%s error=%08lx\n", signal.pid,
                signal.exception.ExceptionCode, signal.context.Eip, ok ? "PASS" : "FAIL", error);
    CloseHandle(file);
    if (ok && CopyFileW(temporary.c_str(), path.c_str(), TRUE)) {
        DeleteFileW(temporary.c_str());
        return true;
    }
    std::printf("heap_dump_retained=%ls copy_error=%08lx\n", temporary.c_str(), GetLastError());
    return false;
}
} // namespace
int wmain(int argc, wchar_t** argv) {
    if (argc != 4)
        return 1;
    const auto lab = fullPath(argv[1]), output = fullPath(argv[2]);
    if (lab.empty() || output.empty() || !std::filesystem::is_regular_file(lab / L".isaac-lan-lab"))
        return 2;
    wchar_t* end = nullptr;
    const auto pid = wcstoul(argv[3], &end, 10);
    if (!pid || *end)
        return 1;
    auto game = lab / L"game" / L"isaac-ng.exe";
    game.make_preferred();
    const auto target = OpenProcess(
        PROCESS_QUERY_INFORMATION | PROCESS_VM_READ | PROCESS_DUP_HANDLE | SYNCHRONIZE, FALSE, pid);
    wchar_t actual[32768]{};
    DWORD size = 32768;
    const bool owned = target && QueryFullProcessImageNameW(target, 0, actual, &size) &&
                       !_wcsicmp(actual, game.c_str());
    if (!owned) {
        if (target)
            CloseHandle(target);
        return 2;
    }
    std::filesystem::create_directories(output);
    wchar_t name[96];
    std::swprintf(name, 96, L"Local\\IsaacLanCrash-%lu", pid);
    const auto mapping = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0,
                                            sizeof(isaac::diagnostics::CrashSignal), name);
    if (!mapping || GetLastError() == ERROR_ALREADY_EXISTS)
        return 3;
    auto signal = static_cast<isaac::diagnostics::CrashSignal*>(MapViewOfFile(
        mapping, FILE_MAP_WRITE | FILE_MAP_READ, 0, 0, sizeof(isaac::diagnostics::CrashSignal)));
    if (!signal)
        return 3;
    std::swprintf(name, 96, L"Local\\IsaacLanCrashRequest-%lu", pid);
    const auto request = CreateEventW(nullptr, FALSE, FALSE, name);
    std::swprintf(name, 96, L"Local\\IsaacLanCrashDone-%lu", pid);
    const auto done = CreateEventW(nullptr, FALSE, FALSE, name);
    if (!request || !done)
        return 3;
    signal->magic = isaac::diagnostics::crashSignalMagic;
    signal->pid = pid;
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::printf("heap_watch_ready pid=%lu\n", pid);
    const HANDLE handles[] = {target, request};
    unsigned ordinal = 0;
    bool failed = false;
    DWORD exit = 0;
    while (true) {
        const auto event = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
        if (event == WAIT_OBJECT_0) {
            GetExitCodeProcess(target, &exit);
            std::printf("heap_game_exit pid=%lu code=%08lx\n", pid, exit);
            break;
        }
        if (event != WAIT_OBJECT_0 + 1) {
            failed = true;
            break;
        }
        if (ordinal < 3)
            failed |= !dump(target, *signal, output, ++ordinal);
        SetEvent(done);
    }
    CloseHandle(done);
    CloseHandle(request);
    UnmapViewOfFile(signal);
    CloseHandle(mapping);
    CloseHandle(target);
    return !exit && !failed ? 0 : 5;
}

// Synthetic debugger regression, not a game or a heap-corruption reproduction.
#include "diagnostics/crash_signal.h"
#include <cstdio>
#include <filesystem>
LONG CALLBACK syntheticCrash(EXCEPTION_POINTERS* exception) {
    isaac::diagnostics::notifyCrash(exception);
    ExitProcess(0xc0000374);
}
int main() {
    wchar_t executable[32768]{};
    GetModuleFileNameW(nullptr, executable, 32768);
    const auto lab = std::filesystem::path(executable).parent_path().parent_path();
    if (!std::filesystem::exists(lab / ".isaac-lan-lab"))
        return 2;
    // The real J460 executable can reserve more than 2 GiB. Reserve a sparse
    // region to exercise dump metadata without allocating that much RAM.
    const auto first = VirtualAlloc(nullptr, 0x50000000, MEM_RESERVE, PAGE_NOACCESS);
    const auto second = VirtualAlloc(nullptr, 0x50000000, MEM_RESERVE, PAGE_NOACCESS);
    if (!first || !second)
        return 6;
    std::printf("fixture_pid=%lu\n", GetCurrentProcessId());
    std::fflush(stdout);
    const auto start = GetTickCount64();
    while (!std::filesystem::exists(lab / "go")) {
        if (GetTickCount64() - start > 20000)
            return 3;
        Sleep(10);
    }
    SetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", lab.c_str());
    AddVectoredExceptionHandler(1, syntheticCrash);
    RaiseException(0xc0000374, EXCEPTION_NONCONTINUABLE, 0, nullptr);
    return 4;
}

#include "diagnostics/crash_signal.h"
#include <cstdio>
#include <cwchar>

namespace isaac::diagnostics {
bool notifyCrash(EXCEPTION_POINTERS* exception) {
    struct PreserveError {
        DWORD value = GetLastError();
        ~PreserveError() {
            SetLastError(value);
        }
    } preserveError;
    const auto code = exception->ExceptionRecord->ExceptionCode;
    if (code != EXCEPTION_ACCESS_VIOLATION && code != 0xc0000374 && code != 0xc0000409)
        return false;
    wchar_t lab[2]{};
    if (!GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", lab, 2))
        return false;
    wchar_t name[96];
    std::swprintf(name, 96, L"Local\\IsaacLanCrash-%lu", GetCurrentProcessId());
    const auto mapping = OpenFileMappingW(FILE_MAP_WRITE | FILE_MAP_READ, FALSE, name);
    if (!mapping)
        return false;
    auto signal = static_cast<CrashSignal*>(
        MapViewOfFile(mapping, FILE_MAP_WRITE | FILE_MAP_READ, 0, 0, sizeof(CrashSignal)));
    if (!signal || signal->magic != crashSignalMagic || signal->pid != GetCurrentProcessId()) {
        if (signal)
            UnmapViewOfFile(signal);
        CloseHandle(mapping);
        return false;
    }
    if (InterlockedCompareExchange(&signal->claimed, 1, 0) != 0) {
        UnmapViewOfFile(signal);
        CloseHandle(mapping);
        return false;
    }
    signal->thread = GetCurrentThreadId();
    signal->exception = *exception->ExceptionRecord;
    signal->context = *exception->ContextRecord;
    std::swprintf(name, 96, L"Local\\IsaacLanCrashRequest-%lu", GetCurrentProcessId());
    const auto request = OpenEventW(EVENT_MODIFY_STATE, FALSE, name);
    std::swprintf(name, 96, L"Local\\IsaacLanCrashDone-%lu", GetCurrentProcessId());
    const auto done = OpenEventW(SYNCHRONIZE, FALSE, name);
    const bool sent = request && done && SetEvent(request);
    const bool observed = sent && WaitForSingleObject(done, 30000) == WAIT_OBJECT_0;
    // A timed-out observer may still be reading this record. Keep it claimed
    // so another exception cannot replace its context halfway through a dump.
    if (observed || !sent)
        InterlockedExchange(&signal->claimed, 0);
    if (request)
        CloseHandle(request);
    if (done)
        CloseHandle(done);
    UnmapViewOfFile(signal);
    CloseHandle(mapping);
    return observed;
}
} // namespace isaac::diagnostics

#pragma once
#include <windows.h>

namespace isaac::diagnostics {
inline constexpr DWORD crashSignalMagic = 0x4c414e44;
struct CrashSignal {
    DWORD magic, pid, thread;
    volatile LONG claimed;
    EXCEPTION_RECORD exception;
    CONTEXT context;
};
// Test-only observation. A marked lab's external observer owns all handles and
// files. The exception handler copies scalar context without heap allocation.
bool notifyCrash(EXCEPTION_POINTERS* exception);
} // namespace isaac::diagnostics

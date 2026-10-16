#include "diagnostics/native_exceptions.h"
#include "diagnostics/crash_signal.h"
#include "diagnostics/runtime_log.h"
#include <windows.h>
#include <cstdio>
#include <string>
namespace isaac::diagnostics {
namespace {
std::uintptr_t image;
bool (*scopeActive)();
template <class T> bool read(std::uintptr_t address, T& value) {
    SIZE_T count = 0;
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(address), &value,
                             sizeof(T), &count) &&
           count == sizeof(T);
}

LONG CALLBACK recordException(EXCEPTION_POINTERS* exception) {
    isaac::diagnostics::notifyCrash(exception);
    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_ACCESS_VIOLATION)
        return EXCEPTION_CONTINUE_SEARCH;
    char line[512];
    snprintf(line, sizeof(line),
             "native_exception=%08lx eip=%08lx ecx=%08lx edx=%08lx scope=%d image=%08lx rva=%08lx "
             "access=%lu address=%08lx",
             exception->ExceptionRecord->ExceptionCode, exception->ContextRecord->Eip,
             exception->ContextRecord->Ecx, exception->ContextRecord->Edx, scopeActive(),
             static_cast<unsigned long>(image),
             exception->ContextRecord->Eip - static_cast<unsigned long>(image),
             static_cast<unsigned long>(exception->ExceptionRecord->ExceptionInformation[0]),
             static_cast<unsigned long>(exception->ExceptionRecord->ExceptionInformation[1]));
    logging::write(line);
    HMODULE faultModule = nullptr;
    if (GetModuleHandleExA(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<const char*>(exception->ContextRecord->Eip), &faultModule)) {
        char path[MAX_PATH]{};
        GetModuleFileNameA(faultModule, path, MAX_PATH);
        snprintf(line, sizeof(line), "native_exception_module=%s rva=%08lx", path,
                 exception->ContextRecord->Eip - reinterpret_cast<DWORD>(faultModule));
        logging::write(line);
    }
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
    logging::write(stack);
    return EXCEPTION_CONTINUE_SEARCH;
}

} // namespace
void observeExceptions(std::uintptr_t base, bool (*scope)()) {
    image = base;
    scopeActive = scope;
    AddVectoredExceptionHandler(1, recordException);
}
} // namespace isaac::diagnostics

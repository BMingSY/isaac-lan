#pragma once
#include <windows.h>
#include <filesystem>
#include <stdexcept>

namespace isaac::engine {
// Resolve the module containing an owned address, rather than guessing a DLL
// filename in the executable directory. Does not acquire another module ref.
inline std::filesystem::path modulePath(const void* address) {
    HMODULE module{};
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            static_cast<LPCWSTR>(address), &module))
        throw std::runtime_error("Cannot locate extension module");
    wchar_t path[32768]{};
    const auto size = GetModuleFileNameW(module, path, std::size(path));
    if (!size || size >= std::size(path))
        throw std::runtime_error("Cannot locate extension module file");
    return path;
}
} // namespace isaac::engine

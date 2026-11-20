#include "engine/native_files.h"
#include "engine/imports.h"
#include <cstring>

namespace isaac::engine::native_files {
namespace {
using Open = void*(__cdecl*)(const char*, const char*);
using StreamOpen = void*(__cdecl*)(const char*, int, int);
constexpr char streamSymbol[] = "?_Fiopen@std@@YAPAU_iobuf@@PBDHH@Z";
constexpr int streamOutput = 2, streamAppend = 8;
Open originalOpen = nullptr;
StreamOpen originalStream = nullptr;
Observer observe = nullptr;
std::uintptr_t installedImage = 0;
void opened(const char* name) noexcept {
    const auto error = GetLastError();
    try {
        if (observe)
            observe(name);
    } catch (...) {
        // Diagnostics must not change the native open's result or last error.
    }
    SetLastError(error);
}
void* __cdecl open(const char* name, const char* mode) {
    const auto file = originalOpen(name, mode);
    if (file && mode && std::strpbrk(mode, "wa+"))
        opened(name);
    return file;
}
void* __cdecl streamOpen(const char* name, int mode, int protection) {
    const auto file = originalStream(name, mode, protection);
    if (file && (mode & (streamOutput | streamAppend)))
        opened(name);
    return file;
}
} // namespace
std::string install(std::uintptr_t image, Observer observer) {
    if (installedImage)
        return installedImage == image && observer == observe ? "" : "native file observer reuse";
    if (!image || !observer)
        return "native file observer configuration";
    observe = observer;
    if (imports::replace(image, "fopen", reinterpret_cast<void*>(open),
                         reinterpret_cast<void**>(&originalOpen)) != imports::Result::replaced) {
        observe = nullptr;
        return "fopen";
    }
    // Original Repentance uses stdio without importing the C++ stream opener.
    // If a stream import exists, inability to hook it still fails startup.
    const auto stream = imports::replace(image, streamSymbol, reinterpret_cast<void*>(streamOpen),
                                         reinterpret_cast<void**>(&originalStream));
    if (stream == imports::Result::failed) {
        imports::replace(image, "fopen", reinterpret_cast<void*>(originalOpen));
        originalOpen = nullptr;
        originalStream = nullptr;
        observe = nullptr;
        return streamSymbol;
    }
    installedImage = image;
    return {};
}
} // namespace isaac::engine::native_files

#pragma once
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <stdexcept>

namespace isaac::presentation {
// Publish complete files only. Both callers own their config/cache subdirectory.
template <typename Writer>
void cacheAsset(const std::filesystem::path& path, const Writer& writeContent) {
    const auto temporary = path.wstring() + L"." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::error_code ignored;
            std::filesystem::remove(path, ignored);
        }
    } cleanup{temporary};
    writeContent(cleanup.path);
    if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING))
        throw std::runtime_error("image_cache_replace");
}
inline void cacheAsset(const std::filesystem::path& path, const char* bytes, std::size_t size) {
    cacheAsset(path, [&](const auto& temporary) {
        std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
        if (!file.write(bytes, size) || !file.flush())
            throw std::runtime_error("image_cache_write");
    });
}
} // namespace isaac::presentation

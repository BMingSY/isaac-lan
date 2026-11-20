#pragma once
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace isaac::presentation {
template <typename Writer>
inline void writeCacheFile(const std::filesystem::path& path, const Writer& writeContent) {
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
inline void writeCacheBytes(const std::filesystem::path& path, const char* bytes,
                            std::size_t size) {
    writeCacheFile(path, [&](const auto& temporary) {
        std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
        if (!file.write(bytes, size) || !file.flush())
            throw std::runtime_error("image_cache_write");
    });
}
inline std::string cacheAnimation(const std::filesystem::path& path, std::string_view descriptor) {
    bool current = false;
    {
        std::ifstream cached(path, std::ios::binary | std::ios::ate);
        if (cached && cached.tellg() == static_cast<std::streamoff>(descriptor.size())) {
            std::string data(descriptor.size(), '\0');
            cached.seekg(0);
            current = cached.read(data.data(), data.size()) && data == descriptor;
        }
    }
    if (!current) {
        std::filesystem::create_directories(path.parent_path());
        writeCacheBytes(path, descriptor.data(), descriptor.size());
    }
    const auto encoded = path.generic_u8string();
    return {encoded.begin(), encoded.end()};
}
} // namespace isaac::presentation

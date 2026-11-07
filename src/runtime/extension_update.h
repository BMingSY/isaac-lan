#pragma once
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace isaac::updates {
using FileHash = std::string (*)(const std::filesystem::path&);
struct Selection {
    std::vector<std::filesystem::path> candidates;
    std::string detail;
};
// Installed root DLL remains the final fallback. Only complete compatible
// packages newer than the loader's installation baseline enter the cache.
Selection select(const std::filesystem::path& game, const std::filesystem::path& workshop,
                 std::string_view baselineVersion, std::string_view gameBuild, FileHash hash);
} // namespace isaac::updates

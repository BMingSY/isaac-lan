#pragma once
#include "core/extension_package.h"
#include <filesystem>
#include <string>
#include <string_view>
#include <vector>

namespace isaac::updates {
using FileHash = std::string (*)(const std::filesystem::path&);
struct Selection {
    std::vector<std::filesystem::path> candidates;
    std::string detail;
    std::optional<Package> newest;
};
// Installed root DLL remains the final fallback. Only complete compatible
// packages newer than the loader's installation baseline enter the cache.
Selection select(const std::filesystem::path& game, const std::filesystem::path& workshop,
                 std::string_view baselineVersion, std::string_view gameBuild, FileHash hash);
// Stages complete packages without loading or executing another DLL. Compare
// against the running extension, not the root installation's older baseline.
std::optional<Package> pending(const std::filesystem::path& game,
                               const std::filesystem::path& workshop,
                               std::string_view runningVersion, std::string_view gameBuild,
                               FileHash hash);
} // namespace isaac::updates

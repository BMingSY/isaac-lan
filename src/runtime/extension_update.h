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
// Only complete compatible updates newer than the installed baseline enter
// the cache. The loader supplies the installed DLL for the active game.
Selection select(const std::filesystem::path& game, const std::filesystem::path& workshop,
                 std::string_view baselineVersion, std::string_view gameBuild, FileHash hash,
                 const std::filesystem::path& installed = {});
// Stages complete packages without loading or executing another DLL. Compare
// against the running extension, not the root installation's older baseline.
std::optional<Package> pending(const std::filesystem::path& game,
                               const std::filesystem::path& workshop,
                               std::string_view runningVersion, std::string_view gameBuild,
                               FileHash hash);
} // namespace isaac::updates

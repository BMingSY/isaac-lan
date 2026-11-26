#pragma once
#include <filesystem>
#include <string>
#include <string_view>

namespace isaac::feedback {
struct CrashReport {
    std::filesystem::path log;
    std::string summary;
};
// Find one native crash belonging to the previous launch. The binary dump stays on disk.
CrashReport previousCrash(const std::filesystem::path& previousLaunch,
                          const std::filesystem::path& currentLaunch, std::string_view gameBuild);
} // namespace isaac::feedback

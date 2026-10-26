#pragma once
#include <filesystem>
#include <string>
#include <string_view>

namespace isaac::app {
struct BridgeManifest {
    std::string fingerprint, mods;
};
BridgeManifest buildManifest(const std::filesystem::path& directory, std::string_view version,
                             void (*logger)(const std::string&));
} // namespace isaac::app

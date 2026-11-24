#pragma once
#include <filesystem>
#include <string>
#include <string_view>

namespace isaac::app {
struct BridgeManifest {
    std::string fingerprint, mods;
    bool stockContent = false;
};
BridgeManifest buildManifest(const std::filesystem::path& directory, std::string_view version,
                             void (*logger)(const std::string&),
                             const std::filesystem::path& extensionPath = {});
} // namespace isaac::app

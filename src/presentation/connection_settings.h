#pragma once
#include <filesystem>
#include <cstdint>
#include <string>

namespace isaac::presentation {
struct ConnectionSettings {
    std::string address;
    unsigned port = 29506;
    std::uint32_t roomOptions = 0;
    bool operator==(const ConnectionSettings&) const = default;
};
// Local menu preferences, independent of sessions and game save slots.
ConnectionSettings loadConnectionSettings(const std::filesystem::path& path);
bool saveConnectionSettings(const std::filesystem::path& path, const ConnectionSettings& settings);
} // namespace isaac::presentation

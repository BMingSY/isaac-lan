#pragma once
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace isaac::engine {
struct GameVersion {
    std::string_view backend, version;
    std::uint32_t markerRva;
};
struct GameDetection {
    const GameVersion* installed{};
    bool ambiguous{};
};
// Compare the complete marker and delimiter at the audited address in the running image.
bool matchesGameVersion(const void* image, std::size_t imageSize, std::string_view version,
                        std::uint32_t markerRva);
GameDetection identifyGame(const void* image, std::size_t imageSize);
} // namespace isaac::engine

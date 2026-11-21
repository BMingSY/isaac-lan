#pragma once
#include <cstddef>
#include <cstdint>
#include <string_view>

namespace isaac::engine {
struct GameVersion {
    std::string_view backend, version;
    std::uint32_t markerRva;
};
// Read the version marker of the running game before selecting an extension.
const GameVersion* identifyGame(const void* image, std::size_t imageSize);
} // namespace isaac::engine

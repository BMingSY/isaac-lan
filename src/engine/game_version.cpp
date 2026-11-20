#include "engine/game_version.h"
#include "supported_game_versions.h"
#include <windows.h>
#include <string>

namespace isaac::engine {
const GameVersion* identifyGame(const void* image, std::size_t imageSize) {
    const GameVersion* match = nullptr;
    for (const auto& candidate : supportedGameVersions) {
        const auto size = candidate.version.size() + 1;
        if (candidate.markerRva > imageSize || size > imageSize - candidate.markerRva)
            continue;
        std::string marker(size, '\0');
        SIZE_T count{};
        const auto address = static_cast<const std::byte*>(image) + candidate.markerRva;
        if (!ReadProcessMemory(GetCurrentProcess(), address, marker.data(), size, &count) ||
            count != size || marker.back() != '-' || !marker.starts_with(candidate.version))
            continue;
        if (match)
            return nullptr;
        match = &candidate;
    }
    return match;
}
} // namespace isaac::engine

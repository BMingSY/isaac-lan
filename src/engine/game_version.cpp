#include "engine/game_version.h"
#include "supported_game_versions.h"
#include <windows.h>
#include <string>

namespace isaac::engine {
bool matchesGameVersion(const void* image, std::size_t imageSize, std::string_view version,
                        std::uint32_t markerRva) {
    const auto size = version.size() + 1;
    if (!image || !markerRva || markerRva > imageSize || size > imageSize - markerRva)
        return false;
    std::string marker(size + 1, '\0');
    SIZE_T count{};
    const auto address = static_cast<const std::byte*>(image) + (markerRva - 1);
    if (!ReadProcessMemory(GetCurrentProcess(), address, marker.data(), marker.size(), &count) ||
        count != marker.size())
        return false;
    // An advertised RVA inside a longer dotted version must not match its suffix.
    return marker.front() != '.' && !(marker.front() >= '0' && marker.front() <= '9') &&
           marker.back() == '-' && std::string_view(marker).substr(1, version.size()) == version;
}

GameDetection identifyGame(const void* image, std::size_t imageSize) {
    GameDetection result;
    for (const auto& candidate : supportedGameVersions) {
        if (!matchesGameVersion(image, imageSize, candidate.version, candidate.markerRva))
            continue;
        if (result.installed)
            return {nullptr, true};
        result.installed = &candidate;
    }
    return result;
}
} // namespace isaac::engine

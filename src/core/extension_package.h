#pragma once
#include <algorithm>
#include <array>
#include <charconv>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace isaac::updates {
inline constexpr unsigned loaderABI = 1;
inline constexpr char manifestMagic[] = "IsaacLANUpdate/1";
inline constexpr char buildManifestMagic[] = "IsaacLANUpdate/2";
inline constexpr char buildManifestFile[] = "manifest-v2.txt";
inline constexpr std::array<std::string_view, 2> editions{"repentance", "repentance_plus"};
inline constexpr char manifestFile[] = "manifest.txt";
inline constexpr char payloadFile[] = "isaac_lan_probe.dll";
inline constexpr char workshopDirectory[] = "isaac-lan-update";
inline constexpr char workshopApp[] = "250900";
inline constexpr char workshopItem[] = "3817760679";
inline constexpr std::size_t maxManifestBytes = 1024;
inline constexpr std::uintmax_t maxPayloadBytes = 64 * 1024 * 1024;
using Version = std::array<std::uint32_t, 3>;

inline bool validGameBuild(std::string_view value) {
    return !value.empty() && value.front() >= '0' && value.front() <= '9' &&
           value.find_first_not_of("0123456789.bJ") == std::string_view::npos;
}

inline bool validBuildMarker(std::string_view build) {
    const auto marker = build.rfind(".J");
    if (marker == build.npos || marker + 2 >= build.size() ||
        build.substr(marker + 2).find_first_not_of("0123456789") != build.npos)
        return false;
    auto release = build.substr(0, marker);
    if (release.ends_with('b'))
        release.remove_suffix(1);
    return !release.empty() && release.front() != '.' && release.back() != '.' &&
           release.find('.') != release.npos && release.find("..") == release.npos &&
           release.find_first_not_of("0123456789.") == release.npos;
}

inline std::optional<Version> parseVersion(std::string_view value) {
    Version result{};
    for (std::size_t i = 0; i < result.size(); ++i) {
        const auto end = i + 1 == result.size() ? value.size() : value.find('.');
        if (end == std::string_view::npos || !end || (end > 1 && value.front() == '0'))
            return {};
        const auto part = value.substr(0, end);
        const auto parsed = std::from_chars(part.data(), part.data() + part.size(), result[i]);
        if (parsed.ec != std::errc{} || parsed.ptr != part.data() + part.size())
            return {};
        value.remove_prefix(end);
        if (i + 1 != result.size())
            value.remove_prefix(1);
    }
    return result;
}

struct Package {
    std::string version, gameBuild, sha256;
    unsigned abi = 0;
    std::string backend;
    std::uint32_t markerRva = 0;
    bool operator==(const Package&) const = default;
    std::string directory() const {
        return version + "-" + sha256 + (markerRva ? "-v2" : "");
    }
};

inline std::optional<Package> parseManifest(std::string_view text) {
    if (text.empty() || text.size() > maxManifestBytes)
        return {};
    auto field = [&](std::string_view prefix) -> std::optional<std::string_view> {
        const auto end = text.find('\n');
        if (end == std::string_view::npos)
            return {};
        auto line = text.substr(0, end);
        if (!line.empty() && line.back() == '\r')
            line.remove_suffix(1);
        text.remove_prefix(end + 1);
        return line.starts_with(prefix) ? std::optional(line.substr(prefix.size())) : std::nullopt;
    };
    const auto magic = field("");
    const auto version = field("version=");
    const auto gameBuild = field("game_build=");
    const auto abi = field("loader_abi=");
    const auto sha256 = field("sha256=");
    if (!magic || (*magic != manifestMagic && *magic != buildManifestMagic) || !version ||
        !gameBuild || !abi || !sha256)
        return {};
    Package package{std::string(*version), std::string(*gameBuild), std::string(*sha256), 0, {}, 0};
    const auto parsed = std::from_chars(abi->data(), abi->data() + abi->size(), package.abi);
    if (!parseVersion(package.version) || !validGameBuild(package.gameBuild) ||
        parsed.ec != std::errc{} || parsed.ptr != abi->data() + abi->size() ||
        package.sha256.size() != 64 ||
        package.sha256.find_first_not_of("0123456789abcdef") != std::string::npos)
        return {};
    if (*magic == buildManifestMagic) {
        const auto backend = field("backend=");
        const auto rva = field("version_rva=");
        if (!backend || std::find(editions.begin(), editions.end(), *backend) == editions.end() ||
            !rva)
            return {};
        const auto end = rva->data() + rva->size();
        const auto number = std::from_chars(rva->data(), end, package.markerRva);
        if (number.ec != std::errc{} || number.ptr != end || package.markerRva == 0 ||
            !validBuildMarker(*gameBuild))
            return {};
        package.backend = *backend;
    }
    if (!text.empty())
        return {};
    return package;
}
} // namespace isaac::updates

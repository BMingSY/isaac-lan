#pragma once
#include <array>
#include <charconv>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace isaac::updates {
inline constexpr unsigned loaderABI = 1;
inline constexpr char manifestMagic[] = "IsaacLANUpdate/1";
inline constexpr char manifestFile[] = "manifest.txt";
inline constexpr char payloadFile[] = "isaac_lan_probe.dll";
inline constexpr char workshopDirectory[] = "isaac-lan-update";
inline constexpr char workshopApp[] = "250900";
inline constexpr char workshopItem[] = "3817760679";
inline constexpr std::size_t maxManifestBytes = 1024;
inline constexpr std::uintmax_t maxPayloadBytes = 64 * 1024 * 1024;
using Version = std::array<std::uint32_t, 3>;

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
    std::string directory() const {
        return version + "-" + sha256;
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
    const auto magic = field(manifestMagic);
    const auto version = field("version=");
    const auto gameBuild = field("game_build=");
    const auto abi = field("loader_abi=");
    const auto sha256 = field("sha256=");
    if (!text.empty() || !magic || !magic->empty() || !version || !gameBuild || !abi || !sha256)
        return {};
    Package package{std::string(*version), std::string(*gameBuild), std::string(*sha256), 0};
    const auto parsed = std::from_chars(abi->data(), abi->data() + abi->size(), package.abi);
    if (!parseVersion(package.version) || package.gameBuild.empty() ||
        package.gameBuild.find_first_not_of("0123456789.J") != std::string::npos ||
        parsed.ec != std::errc{} || parsed.ptr != abi->data() + abi->size() ||
        package.sha256.size() != 64 ||
        package.sha256.find_first_not_of("0123456789abcdef") != std::string::npos)
        return {};
    return package;
}
} // namespace isaac::updates

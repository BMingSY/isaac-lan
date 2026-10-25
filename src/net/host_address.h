#pragma once
#include <algorithm>
#include <charconv>
#include <cstdint>
#include <string_view>

namespace isaac::lan {
inline constexpr std::size_t maxHostAddressLength = 253;
inline bool hostNameCharacter(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' ||
           c == '-';
}
inline bool hostAddressCharacter(unsigned char c) {
    return hostNameCharacter(c) || c == ':' || c == '[' || c == ']' || c == '%';
}
inline std::string_view unbracketHostAddress(std::string_view address) {
    return address.starts_with('[') && address.ends_with(']')
               ? address.substr(1, address.size() - 2)
               : address;
}
inline bool validHostAddress(std::string_view address) {
    if (address.empty() || address.size() > maxHostAddressLength)
        return false;
    const auto host = unbracketHostAddress(address);
    if (host.find(':') == host.npos)
        return host == address && std::all_of(host.begin(), host.end(), hostNameCharacter);
    auto literal = host;
    if (const auto zone = literal.find('%'); zone != literal.npos) {
        const auto scope = literal.substr(zone + 1);
        std::uint32_t index;
        const auto result = std::from_chars(scope.data(), scope.data() + scope.size(), index);
        if (scope.empty() || result.ec != std::errc{} || result.ptr != scope.data() + scope.size())
            return false;
        literal = literal.substr(0, zone);
    }
    // Winsock validates IPv6 compression, groups and embedded IPv4 octets.
    // Reject field separators, nonnumeric zones and host:port input here.
    return std::count(literal.begin(), literal.end(), ':') >= 2 &&
           std::all_of(literal.begin(), literal.end(), [](unsigned char c) {
               return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') ||
                      c == ':' || c == '.';
           });
}
} // namespace isaac::lan

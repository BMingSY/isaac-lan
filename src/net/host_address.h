#pragma once
#include <algorithm>
#include <string_view>

namespace isaac::lan {
inline constexpr std::size_t maxHostAddressLength = 253;
inline bool hostAddressCharacter(unsigned char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' ||
           c == '-';
}
inline bool validHostAddress(std::string_view address) {
    return !address.empty() && address.size() <= maxHostAddressLength &&
           std::all_of(address.begin(), address.end(), hostAddressCharacter);
}
} // namespace isaac::lan

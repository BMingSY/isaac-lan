#pragma once
#include <cstdint>
#include <limits>

namespace isaac::party {
// Each connected, ready and voting mask carries one bit per LAN seat.
inline constexpr unsigned maxPlayers = std::numeric_limits<std::uint8_t>::digits;
inline constexpr unsigned allPlayersMask = (1u << maxPlayers) - 1;
template <typename T> constexpr bool validSlot(T slot) {
    return slot >= 0 && slot < static_cast<T>(maxPlayers);
}
} // namespace isaac::party

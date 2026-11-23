#pragma once
#include <cstddef>
#include <cstdint>
namespace isaac::lan::datagram {
inline constexpr std::uint8_t reliableChannel = 0, inputChannel = 1, worldChannel = 2,
                              recoveryChannel = 3, detailChannel = 4;
inline constexpr std::size_t channelCount = 5, mtu = 1200;
// Generation fences precede new run/floor input and state on the reliable channel.
enum class Envelope : std::uint8_t {
    message,
    world,
    fence,
    dependency,
    shard,
    compatibility = 5,
    quality,
    detail,
    delivered
};
} // namespace isaac::lan::datagram

#pragma once
#include <cstdint>
#include <span>
#include <vector>

namespace isaac::compression {
std::vector<std::uint8_t> deflate(std::span<const std::uint8_t>, std::size_t limit);
std::vector<std::uint8_t> inflate(std::span<const std::uint8_t>, std::size_t size,
                                  std::size_t limit);
} // namespace isaac::compression

#pragma once
#include <cstdint>
#include <span>
#include <vector>

namespace isaac::save {
// The native GameState serializer supplies the same portable representation
// used by Continue. It does not contain process pointers or copied game code.
std::vector<std::uint8_t> encode(std::uintptr_t image);
bool decode(std::uintptr_t image, std::span<const std::uint8_t> bytes);
std::vector<std::uint8_t> encodeAt(std::uintptr_t image, std::uintptr_t state);
bool decodeAt(std::uintptr_t image, std::uintptr_t state, std::span<const std::uint8_t> bytes);
std::vector<std::uint8_t> capture(std::uintptr_t image);
} // namespace isaac::save

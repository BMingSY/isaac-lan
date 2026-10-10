#pragma once
#include <array>
#include <cstdint>

namespace isaac::engine::j460 {
inline constexpr char version[] = "1.9.7.17.J460";
inline constexpr std::uint32_t versionRva = 0x77b2f4;
inline constexpr std::uint32_t minimumImageSize = 0x89caa4;
struct RequiredSection {
    std::uint32_t start, size, flags;
};
inline constexpr std::array requiredSections = {
    RequiredSection{0x1000, 0x716134, 0x60000000},
    RequiredSection{0x718000, 0xdf948, 0x40000000},
    RequiredSection{0x7f8000, 0xa4aa4, 0xc0000000},
};
} // namespace isaac::engine::j460

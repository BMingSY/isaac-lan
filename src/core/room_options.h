#pragma once
#include <array>
#include <cstdint>
#include <string_view>

namespace isaac::roomOptions {
inline constexpr std::uint32_t friendlyFire = 1u << 0;
inline constexpr std::uint32_t known = friendlyFire;
struct Definition {
    std::uint32_t flag;
    std::string_view key, name;
};
inline constexpr std::array definitions{Definition{friendlyFire, "friendlyFire", "队友伤害"}};
inline bool valid(std::uint32_t value) {
    return !(value & ~known);
}
} // namespace isaac::roomOptions

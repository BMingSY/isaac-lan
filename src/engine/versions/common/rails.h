#pragma once
#include <algorithm>
#include <cstdint>
#include <span>
#include <stdexcept>

namespace isaac::engine::native_rails {
static_assert(sizeof(std::uintptr_t) == 4);
// RailManager owns a fixed 448-byte grid, separately from GridEntity allocations.
inline constexpr unsigned count = 448;
struct Layout {
    unsigned grid, owner, width, height;
};
inline bool valid(std::uint8_t value) {
    return value <= 10 || (value >= 64 && value <= 70) || value == 16 || value == 17 ||
           value == 32 || value == 33 || (value >= 80 && value <= 85) ||
           (value >= 96 && value <= 101) || value == 112 || value == 113 || value == 144 ||
           value == 145 || value == 160 || value == 161 || value == 255;
}
inline std::span<std::uint8_t, count> grid(std::uintptr_t room, const Layout& layout) {
    const auto field = [room](unsigned at) { return *reinterpret_cast<unsigned*>(room + at); };
    if (!room || field(layout.width) < 1 || field(layout.width) > 28 || field(layout.height) < 1 ||
        field(layout.height) > 16 || field(layout.width) * field(layout.height) > count ||
        *reinterpret_cast<std::uintptr_t*>(room + layout.owner) != room)
        throw std::runtime_error("Invalid native rail room");
    return std::span<std::uint8_t, count>(reinterpret_cast<std::uint8_t*>(room + layout.grid),
                                          count);
}
inline void restore(std::uintptr_t room, const Layout& layout,
                    std::span<const std::uint8_t> value) {
    if (value.size() != count || !std::all_of(value.begin(), value.end(), valid))
        throw std::runtime_error("Invalid room rails");
    const auto target = grid(room, layout);
    // No allocation, Sprite ownership or gameplay initialization is involved.
    std::copy(value.begin(), value.end(), target.begin());
}
} // namespace isaac::engine::native_rails

#pragma once
#include "engine/versions/common/player_seats.h"
#include <bit>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>

namespace isaac::engine::native_player_hud {
// The game allocates four main panels followed by four companion panels.
// Their native strides and offsets are independent of the LAN roster size.
inline constexpr unsigned primaryPanels = 4;
inline constexpr unsigned totalPanels = primaryPanels * 2;
inline bool localOnly(unsigned connectedMask) {
    return static_cast<unsigned>(std::popcount(connectedMask)) > primaryPanels;
}
inline unsigned seatBit(int slot) {
    return slot >= 0 && slot < std::numeric_limits<unsigned>::digits ? 1u << slot : 0u;
}
struct Layout {
    unsigned visible, stride, player, controller;
};
struct Anchor {
    int slot, layout;
    float x, y;
};
template <class T> T read(std::uintptr_t address, unsigned offset) {
    T value;
    std::memcpy(&value, reinterpret_cast<const void*>(address + offset), sizeof(value));
    return value;
}
// Borrow the four primary HUDs only; twins share a controller. Native position
// and layout functions must run in the same local-view roster as HUD::Render.
// Return scalar copies, never a player/HUD pointer or an owned native object.
template <class SelectLayout, class Position>
std::optional<Anchor> anchor(std::uintptr_t hud, unsigned index, float width, float height,
                             unsigned audience, const Layout& fields, SelectLayout layout,
                             Position position) {
    if (!hud || index >= primaryPanels || !std::isfinite(width) || !std::isfinite(height) ||
        width <= 0 || height <= 0 || !read<bool>(hud, fields.visible))
        return {};
    const auto player = read<std::uintptr_t>(hud + index * fields.stride, fields.player);
    if (!player)
        return {};
    const auto controller =
        isaac::engine::player_seats::owner(player, read<int>(player, fields.controller));
    if (controller < 1 || !(audience & seatBit(controller - 1)))
        return {};
    const int mode = layout(hud, index, player);
    if (mode < 0 || mode > 3)
        return {};
    float point[2]{};
    position(hud, point, index, mode);
    if (!std::isfinite(point[0]) || !std::isfinite(point[1]) || point[0] < 0 || point[0] > width ||
        point[1] < 0 || point[1] > height)
        return {};
    return Anchor{controller - 1, mode, point[0], point[1]};
}
} // namespace isaac::engine::native_player_hud

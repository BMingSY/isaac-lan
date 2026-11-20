#pragma once
#include <cmath>
#include <cstdint>
#include <cstring>
#include <optional>

namespace isaac::engine::native_player_hud {
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
                             const Layout& fields, SelectLayout layout, Position position) {
    if (!hud || index >= 4 || !std::isfinite(width) || !std::isfinite(height) || width <= 0 ||
        height <= 0 || !read<bool>(hud, fields.visible))
        return {};
    const auto player = read<std::uintptr_t>(hud + index * fields.stride, fields.player);
    if (!player)
        return {};
    const auto controller = read<int>(player, fields.controller);
    if (controller < 1 || controller > 4)
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

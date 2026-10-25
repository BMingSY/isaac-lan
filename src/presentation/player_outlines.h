#pragma once
#include <array>
#include <optional>

namespace isaac::presentation {
struct PlayerOutlineColor {
    float red, green, blue;
};
// Original multiplayer palette: P1 red, P2 blue, P3 yellow, P4 green.
// The renderer uses each channel as both a multiplier and an additive offset.
inline constexpr std::array<PlayerOutlineColor, 4> playerOutlineColors{{
    {112.f / 255, 12.f / 255, 12.f / 255},
    {89.f / 255, 115.f / 255, 147.f / 255},
    {158.f / 255, 150.f / 255, 0},
    {63.f / 255, 94.f / 255, 47.f / 255},
}};
inline std::optional<unsigned> playerOutlineSlot(int slot, unsigned connected) {
    constexpr unsigned participants = (1u << playerOutlineColors.size()) - 1;
    connected &= participants;
    if (!connected || !(connected & (connected - 1)) || slot < 0 ||
        slot >= static_cast<int>(playerOutlineColors.size()) || !(connected & (1u << slot)))
        return {};
    return static_cast<unsigned>(slot);
}
} // namespace isaac::presentation

#pragma once
#include <array>
#include <cstdint>
#include <functional>
#include <optional>

namespace isaac::presentation::player_opacity {
struct Layout {
    unsigned controller;
    std::array<unsigned, 4> sprites;
    unsigned costumesBegin, costumesEnd, costumeStride, maximumCostumes;
};
extern const Layout layoutFields;
// Borrowed addresses are valid only inside withPlayers and withSprite. A
// present factor of one still overrides Plus's unrelated native online fade.
bool playersActive();
std::optional<float> spriteFactor(std::uintptr_t sprite);
std::optional<float> playerFactor(std::uintptr_t player);
void withSprite(std::uintptr_t sprite, float factor, const std::function<void()>& render);
} // namespace isaac::presentation::player_opacity

#pragma once
#include "presentation/player_outlines.h"
namespace isaac::presentation::outlines {
using Color = std::array<float, 11>;
inline unsigned participants = 0;
inline std::optional<unsigned> controllerSlot(int controller) {
    return controller > 0 ? playerOutlineSlot(controller - 1, participants) : std::nullopt;
}
inline Color nativeColor(unsigned slot) {
    const auto& color = playerOutlineColors[slot];
    return {color.red, color.green, color.blue, 1, 0, 0, 0, 0, color.red, color.green, color.blue};
}
} // namespace isaac::presentation::outlines

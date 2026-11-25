#pragma once
#include "engine/versions/common/player_hud.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::repentance_plus::player_hud {
using Anchor = native_player_hud::Anchor;
inline constexpr native_player_hud::Layout fields{layout::hud::visible, layout::playerHud::size,
                                                  layout::playerHud::player,
                                                  layout::player::controller};
template <class SelectLayout, class Position>
std::optional<Anchor> anchor(std::uintptr_t hud, unsigned index, float width, float height,
                             SelectLayout layout, Position position, unsigned audience) {
    return native_player_hud::anchor(hud, index, width, height, audience, fields, layout, position);
}
} // namespace isaac::engine::repentance_plus::player_hud

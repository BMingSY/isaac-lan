#pragma once
#include "engine/versions/common/player_hud.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::j460::player_hud {
using Anchor = native_player_hud::Anchor;
inline constexpr native_player_hud::Layout fields{layout::hud::visible, layout::playerHud::size,
                                                  layout::playerHud::player,
                                                  layout::player::controller};
template <class SelectLayout, class Position>
std::optional<Anchor> anchor(std::uintptr_t hud, unsigned index, float width, float height,
                             SelectLayout layout, Position position) {
    return native_player_hud::anchor(hud, index, width, height, fields, layout, position);
}
} // namespace isaac::engine::j460::player_hud

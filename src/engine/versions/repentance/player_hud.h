#pragma once
#include "engine/versions/common/player_hud.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::repentance::player_hud {
using Anchor = native_player_hud::Anchor;
inline constexpr native_player_hud::Layout fields{layout::hud::visible, layout::playerHud::size,
                                                  layout::playerHud::player,
                                                  layout::player::controller};
// Repentance has no separate layout/position methods. HUD::Render constructs these
// four heart anchors inline before its RenderHearts call at 0x505965. Primary
// corners follow the HUD array; network identity comes from its bound player.
inline std::optional<Anchor> anchor(std::uintptr_t hud, unsigned index, float width, float height,
                                    float hudOffset) {
    if (!std::isfinite(hudOffset))
        return {};
    return native_player_hud::anchor(
        hud, index, width, height, fields,
        [](auto, auto corner, auto) { return static_cast<int>(corner); },
        [hudOffset, width, height](auto, float* point, auto corner, auto) {
            const float margin = 1 - hudOffset;
            const auto& origin = layout::hud::heartOrigins[corner];
            const auto& inset = layout::hud::heartMargins[corner];
            point[0] = origin[0] + margin * inset[0];
            point[1] = origin[1] + margin * inset[1];
            if (point[0] < 0)
                point[0] += width;
            if (point[1] < 0)
                point[1] += height;
        });
}
} // namespace isaac::engine::repentance::player_hud

#pragma once
#include "compat/game_ids.h"
#include <optional>

namespace isaac::compat::routes {
inline std::optional<int> mirrorEntrance(int animation, int leaveDoor) {
    // The mirror connects two versions of the same doorway. Screen mirroring
    // changes its displayed side, but does not move its world-space door slot.
    if (animation == ids::roomTransition::mirror && leaveDoor >= 0 && leaveDoor < 8)
        return leaveDoor;
    return std::nullopt;
}
} // namespace isaac::compat::routes

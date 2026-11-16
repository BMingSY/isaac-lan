#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::routes {
inline bool mistFamiliarQuery(int type, int variant, int subtype) {
    constexpr int any = -1, wisp = 88, itemWisp = 202, abyssLocust = 231;
    return type == ids::entity::familiar && subtype == any &&
           (variant == any || variant == wisp || variant == itemWisp || variant == abyssLocust);
}
inline bool escapeFollower(unsigned entityType, int dimension, bool escaping, bool lastOccupant) {
    return entityType == ids::entity::mothersShadow && dimension == ids::dimension::minesEscape &&
           escaping && lastOccupant;
}
} // namespace isaac::compat::routes

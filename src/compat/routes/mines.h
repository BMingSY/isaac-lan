#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::routes {
inline bool escapeFollower(unsigned entityType, int dimension, bool escaping, bool lastOccupant) {
    return entityType == ids::entity::mothersShadow && dimension == ids::dimension::minesEscape &&
           escaping && lastOccupant;
}
} // namespace isaac::compat::routes

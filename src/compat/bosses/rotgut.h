#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::bosses {
// Rotgut's first phase swallows every player in its room, then requests the
// first stomach with a null actor. Later crawlspace doors remain per player.
inline bool rotgutSwallow(int index, int direction, int animation, int dimension,
                          unsigned entityType, unsigned variant) {
    return index == -14 && direction == -1 && animation == 2 &&
           (dimension == -1 || dimension == 0) && entityType == ids::entity::rotgut && variant == 0;
}
// Once the heart is gone, native Room::Update returns the room's survivors
// together, again without an actor. Ordinary crawlspace exits stay per player.
inline bool rotgutReturn(int source, int index, int origin, int direction, int animation,
                         int dimension) {
    return source == -15 && index == origin && origin >= -20 && origin < 169 && origin != -14 &&
           origin != -15 && direction == -1 && animation == 0 &&
           (dimension == -1 || dimension == 0);
}
} // namespace isaac::compat::bosses

#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::characters {
enum class TeamEffect { shop, randomCollectibles, randomCards };
inline bool sharedCharacterEffect(int kind, TeamEffect effect) {
    return (kind == ids::player::keeperB && effect == TeamEffect::shop) ||
           (kind == ids::player::lostB &&
            (effect == TeamEffect::randomCollectibles || effect == TeamEffect::randomCards));
}
} // namespace isaac::compat::characters

#pragma once
#include "compat/game_ids.h"
#include <cstdint>

namespace isaac::presentation {
// Water spray is generated locally from the synchronized room current. Pickup
// ghosts own process-local LootList/ANM2 objects and are regenerated for the local
// holder. Neither can be reconstructed from a generic entity snapshot. Other
// splash subtypes, creep and gameplay effects remain authoritative.
constexpr bool localAmbientEffect(std::int64_t type, std::int64_t variant, std::int64_t subtype) {
    return type == compat::ids::entity::effect &&
           ((variant == compat::ids::effect::waterSplash && subtype == 1) ||
            variant == compat::ids::effect::pickupGhost);
}
} // namespace isaac::presentation

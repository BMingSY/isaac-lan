#pragma once
#include "compat/game_ids.h"
#include <cstdint>

namespace isaac::presentation {
// Native current spray is a short-lived visual particle. Both peers already
// generate it from the synchronized room current; it has no authority identity or AI.
// Keep other splash subtypes, creep and gameplay effects authoritative.
constexpr bool localAmbientEffect(std::int64_t type, std::int64_t variant, std::int64_t subtype) {
    return type == compat::ids::entity::effect && variant == compat::ids::effect::waterSplash &&
           subtype == 1;
}
} // namespace isaac::presentation

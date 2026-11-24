#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::routes {
constexpr bool crawlspaceStairs(int source, int destination, int animation) {
    return animation == ids::roomTransition::pixelation &&
           (source == ids::gridRoom::dungeon || destination == ids::gridRoom::dungeon);
}
} // namespace isaac::compat::routes

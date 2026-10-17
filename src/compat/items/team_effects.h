#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::items {
inline bool sharedCollectibleEffect(int item) {
    // Add shared passive effects here; inventories and personal synergies
    // remain owned by their original player.
    return item == ids::collectible::compass || item == ids::collectible::treasureMap ||
           item == ids::collectible::steamSale || item == ids::collectible::blueMap ||
           item == ids::collectible::blackCandle || item == ids::collectible::restock ||
           item == ids::collectible::chaos || item == ids::collectible::sacredOrb ||
           item == ids::collectible::damoclesPassive || item == ids::collectible::tmtrainer;
}
} // namespace isaac::compat::items

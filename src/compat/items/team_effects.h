#pragma once
#include <algorithm>
#include <array>
#include "compat/game_ids.h"

namespace isaac::compat::items {
// Add shared passive effects here; inventories and personal synergies
// remain owned by their original player.
inline constexpr std::array sharedCollectibles{
    ids::collectible::compass,     ids::collectible::treasureMap,
    ids::collectible::steamSale,   ids::collectible::blueMap,
    ids::collectible::blackCandle, ids::collectible::mind,
    ids::collectible::restock,     ids::collectible::chaos,
    ids::collectible::sacredOrb,   ids::collectible::damoclesPassive,
    ids::collectible::tmtrainer,   ids::collectible::theresOptions,
    ids::collectible::moreOptions, ids::collectible::options,
};

inline bool sharedCollectibleEffect(int item) {
    return std::find(sharedCollectibles.begin(), sharedCollectibles.end(), item) !=
           sharedCollectibles.end();
}
} // namespace isaac::compat::items

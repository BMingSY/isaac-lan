#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::bosses {
inline constexpr unsigned dogmaTelevisionVariant = 4;
inline bool gatherHomeCombat(int stage, int kind, bool dogma, unsigned audience,
                             unsigned connected) {
    return stage == ids::stage::home && kind == ids::stageType::wrathOfTheLamb && dogma &&
           (audience & connected) != connected;
}
inline bool finalCombat(int stage, int kind, unsigned entityType, unsigned variant = 0,
                        unsigned difficulty = 0) {
    if (difficulty == ids::difficulty::greed || difficulty == ids::difficulty::greedier)
        return stage == ids::stage::greedFinal && entityType == ids::entity::ultraGreed;
    if (stage == ids::stage::chestOrDarkRoom &&
        (kind == ids::stageType::original || kind == ids::stageType::wrathOfTheLamb))
        return entityType == ids::entity::isaac || entityType == ids::entity::lamb ||
               entityType == ids::entity::megaSatan || entityType == ids::entity::megaSatanSecond;
    if (stage == ids::stage::voidFloor)
        return entityType == ids::entity::delirium;
    if (stage == ids::stage::blueWomb && kind == ids::stageType::original)
        return entityType == ids::entity::ultraGreed || entityType == ids::entity::hush;
    if (stage == ids::stage::chapterFourSecond &&
        (kind == ids::stageType::repentance || kind == ids::stageType::repentanceB))
        return entityType == ids::entity::mother;
    return stage == ids::stage::home && kind == ids::stageType::wrathOfTheLamb &&
           (entityType == ids::entity::dogma || entityType == ids::entity::beast ||
            (entityType == ids::entity::genericProp && variant == dogmaTelevisionVariant));
}
} // namespace isaac::compat::bosses

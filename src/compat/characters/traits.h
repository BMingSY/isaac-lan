#pragma once
#include "compat/game_ids.h"

namespace isaac::compat::characters {
inline constexpr int lazarusLiving = ids::player::lazarusB;
inline constexpr int lazarusDead = ids::player::lazarusSecondB;
inline constexpr unsigned darkEsau = ids::entity::darkEsau;
inline bool lazarus(int kind) {
    return kind == lazarusLiving || kind == lazarusDead;
}
inline bool forgotten(int kind) {
    return kind == ids::player::forgotten || kind == ids::player::soul;
}
inline bool taintedJacob(int kind) {
    return kind == ids::player::jacobB || kind == ids::player::jacobSecondB;
}
} // namespace isaac::compat::characters

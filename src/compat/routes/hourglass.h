#pragma once
#include "compat/game_ids.h"
#include <cstdint>

namespace isaac::compat::routes {
// The light selects Cathedral before the deferred departure checkpoint is
// taken. Rewinding to either fork restores the choice of exits. The live
// departure and checkpoints on the chosen route keep their original flags.
inline std::uint64_t hourglassCheckpointFlags(int stage, int type, std::uint64_t flags) {
    constexpr auto heaven = std::uint64_t{1} << ids::gameStateFlag::heavenPath;
    constexpr auto backwards = std::uint64_t{1} << ids::gameStateFlag::backwardsPath;
    if ((stage == ids::stage::chapterFourSecond || stage == ids::stage::blueWomb) &&
        type >= ids::stageType::original && type < ids::stageType::repentance &&
        !(flags & backwards))
        return flags & ~heaven;
    return flags;
}
} // namespace isaac::compat::routes

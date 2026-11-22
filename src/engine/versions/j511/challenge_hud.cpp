#include "engine/versions/common/challenge_hud_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_challenge_hud {
namespace {
void writeParameters(Parameters& parameters, std::array<int, 2> goal) {
    parameters[j511::layout::challengeParams::stage / sizeof(std::uint32_t)] = goal[0];
    parameters[j511::layout::challengeParams::destinationType / sizeof(std::uint32_t)] = goal[1];
}
} // namespace
// GetChallengeParams runs normally; only its result inside HUD::Render is
// substituted. Other native callers never encounter this view.
const Bindings bindings{j511::entry::hUDChallengeDestination,
                        j511::entry::hUDChallengeParamsReturn,
                        ecx,
                        eax,
                        j511::layout::challengeHudFrame::noUnlocks,
                        writeParameters};
} // namespace isaac::engine::native_challenge_hud

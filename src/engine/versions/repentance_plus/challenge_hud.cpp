#include "engine/versions/common/challenge_hud_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_challenge_hud {
namespace {
void writeParameters(Parameters& parameters, std::array<int, 2> goal) {
    parameters[repentance_plus::layout::challengeParams::stage / sizeof(std::uint32_t)] = goal[0];
    parameters[repentance_plus::layout::challengeParams::destinationType / sizeof(std::uint32_t)] =
        goal[1];
}
} // namespace
// GetChallengeParams runs normally; only its result inside HUD::Render is
// substituted. Other native callers never encounter this view.
const Bindings bindings{repentance_plus::entry::hUDChallengeDestination,
                        repentance_plus::entry::hUDChallengeParamsReturn,
                        ecx,
                        eax,
                        repentance_plus::layout::challengeHudFrame::noUnlocks,
                        writeParameters};
} // namespace isaac::engine::native_challenge_hud

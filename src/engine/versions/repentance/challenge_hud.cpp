#include "engine/versions/common/challenge_hud_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_challenge_hud {
namespace {
void writeParameters(Parameters& parameters, std::array<int, 2> goal) {
    parameters[repentance::layout::challengeParams::stage / sizeof(std::uint32_t)] = goal[0];
    // Repentance's HUD consumes the legacy path flags. Repentance+'s destination type
    // encodes alternate (1) and secret (2) paths in a single scalar instead.
    constexpr int alternate = 1, secret = 2;
    auto* bytes = reinterpret_cast<std::uint8_t*>(parameters.data());
    bytes[repentance::layout::challengeParams::alternatePath] = goal[1] == alternate;
    bytes[repentance::layout::challengeParams::secretPath] = goal[1] == secret;
}
} // namespace
// The lookup is inlined in HUD::Render. Both its ordinary and daily challenge
// branches converge here with ECX=ChallengeParams; no getter is hooked.
const Bindings bindings{repentance::entry::hUDChallengeDestination,
                        repentance::entry::hUDChallengeParamsRead,
                        edx,
                        ecx,
                        repentance::layout::challengeHudFrame::noUnlocks,
                        writeParameters};
} // namespace isaac::engine::native_challenge_hud

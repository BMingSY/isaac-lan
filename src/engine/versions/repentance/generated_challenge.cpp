#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_generated_challenge {
constinit const Bindings bindings{
    repentance::globals::game,
    repentance::layout::game::challenge,
    repentance::entry::gameGetChestEnding,
    {repentance::entry::glitchedGridStyle, repentance::entry::glitchedRockStyle,
     repentance::entry::glitchedBackdropType, repentance::entry::glitchedBackdropStyle,
     repentance::entry::glitchedRoomConfig}};
} // namespace isaac::engine::native_generated_challenge

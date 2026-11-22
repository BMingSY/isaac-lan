#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_generated_challenge {
constinit const Bindings bindings{
    repentance_plus::globals::game,
    repentance_plus::layout::game::challenge,
    repentance_plus::entry::gameGetChestEnding,
    {repentance_plus::entry::glitchedGridStyle, repentance_plus::entry::glitchedRockStyle,
     repentance_plus::entry::glitchedBackdropType, repentance_plus::entry::glitchedBackdropStyle,
     repentance_plus::entry::glitchedRoomConfig}};
} // namespace isaac::engine::native_generated_challenge

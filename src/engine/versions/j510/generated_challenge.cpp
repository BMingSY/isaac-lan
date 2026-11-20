#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_generated_challenge {
constinit const Bindings bindings{j510::globals::game,
                                  j510::layout::game::challenge,
                                  j510::entry::gameGetChestEnding,
                                  {j510::entry::glitchedGridStyle, j510::entry::glitchedRockStyle,
                                   j510::entry::glitchedBackdropType,
                                   j510::entry::glitchedBackdropStyle,
                                   j510::entry::glitchedRoomConfig}};
} // namespace isaac::engine::native_generated_challenge

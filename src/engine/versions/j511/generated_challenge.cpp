#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_generated_challenge {
constinit const Bindings bindings{j511::globals::game,
                                  j511::layout::game::challenge,
                                  j511::entry::gameGetChestEnding,
                                  {j511::entry::glitchedGridStyle, j511::entry::glitchedRockStyle,
                                   j511::entry::glitchedBackdropType,
                                   j511::entry::glitchedBackdropStyle,
                                   j511::entry::glitchedRoomConfig}};
} // namespace isaac::engine::native_generated_challenge

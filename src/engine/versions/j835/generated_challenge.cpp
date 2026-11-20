#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_generated_challenge {
constinit const Bindings bindings{j835::globals::game,
                                  j835::layout::game::challenge,
                                  j835::entry::gameGetChestEnding,
                                  {j835::entry::glitchedGridStyle, j835::entry::glitchedRockStyle,
                                   j835::entry::glitchedBackdropType,
                                   j835::entry::glitchedBackdropStyle,
                                   j835::entry::glitchedRoomConfig}};
} // namespace isaac::engine::native_generated_challenge

#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_generated_challenge {
constinit const Bindings bindings{j460::globals::game,
                                  j460::layout::game::challenge,
                                  j460::entry::gameGetChestEnding,
                                  {j460::entry::glitchedGridStyle, j460::entry::glitchedRockStyle,
                                   j460::entry::glitchedBackdropType,
                                   j460::entry::glitchedBackdropStyle,
                                   j460::entry::glitchedRoomConfig}};
} // namespace isaac::engine::native_generated_challenge

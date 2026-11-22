#include "engine/versions/common/audio_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_audio {
const Bindings bindings{.entry = {j511::entry::audioPlay, j511::entry::musicPlay,
                                  j511::entry::musicCrossfade, j511::entry::roomUpdateMusic},
                        .globals = {j511::globals::game, j511::globals::manager},
                        .layout = {j511::layout::game::room, j511::layout::game::roomIndex,
                                   j511::layout::game::dimension, j511::layout::manager::music,
                                   j511::layout::manager::options,
                                   j511::layout::options::musicVolume,
                                   j511::layout::music::currentId, j511::layout::music::queuedId}};
} // namespace isaac::engine::native_audio

#include "engine/versions/common/audio_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_audio {
const Bindings bindings{.entry = {j835::entry::audioPlay, j835::entry::musicPlay,
                                  j835::entry::musicCrossfade, j835::entry::roomUpdateMusic},
                        .globals = {j835::globals::game, j835::globals::manager},
                        .layout = {j835::layout::game::room, j835::layout::game::roomIndex,
                                   j835::layout::game::dimension, j835::layout::manager::music,
                                   j835::layout::manager::options,
                                   j835::layout::options::musicVolume,
                                   j835::layout::music::currentId, j835::layout::music::queuedId}};
} // namespace isaac::engine::native_audio

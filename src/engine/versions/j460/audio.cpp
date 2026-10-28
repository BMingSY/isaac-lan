#include "engine/versions/common/audio_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_audio {
const Bindings bindings{.entry = {j460::entry::audioPlay, j460::entry::musicPlay,
                                  j460::entry::musicCrossfade, j460::entry::roomUpdateMusic},
                        .globals = {j460::globals::game, j460::globals::manager},
                        .layout = {j460::layout::game::room, j460::layout::game::roomIndex,
                                   j460::layout::game::dimension, j460::layout::manager::music,
                                   j460::layout::manager::options,
                                   j460::layout::options::musicVolume,
                                   j460::layout::music::currentId, j460::layout::music::queuedId}};
} // namespace isaac::engine::native_audio

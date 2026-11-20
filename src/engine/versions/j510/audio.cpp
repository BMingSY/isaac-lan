#include "engine/versions/common/audio_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_audio {
const Bindings bindings{.entry = {j510::entry::audioPlay, j510::entry::musicPlay,
                                  j510::entry::musicCrossfade, j510::entry::roomUpdateMusic},
                        .globals = {j510::globals::game, j510::globals::manager},
                        .layout = {j510::layout::game::room, j510::layout::game::roomIndex,
                                   j510::layout::game::dimension, j510::layout::manager::music,
                                   j510::layout::manager::options,
                                   j510::layout::options::musicVolume,
                                   j510::layout::music::currentId, j510::layout::music::queuedId}};
} // namespace isaac::engine::native_audio

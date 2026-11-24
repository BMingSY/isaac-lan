#include "engine/versions/common/audio_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_audio {
const Bindings bindings{
    .entry = {repentance::entry::audioPlay, repentance::entry::audioUpdateLoop,
              repentance::entry::roomUpdateAmbience, repentance::entry::musicPlay,
              repentance::entry::musicCrossfade, repentance::entry::roomUpdateMusic},
    .globals = {repentance::globals::game, repentance::globals::manager},
    .layout = {repentance::layout::game::room, repentance::layout::game::roomIndex,
               repentance::layout::game::dimension, repentance::layout::manager::music,
               repentance::layout::manager::options, repentance::layout::options::musicVolume,
               repentance::layout::music::currentId, repentance::layout::music::queuedId}};
} // namespace isaac::engine::native_audio

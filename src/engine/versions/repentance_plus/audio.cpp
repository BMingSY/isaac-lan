#include "engine/versions/common/audio_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_audio {
const Bindings bindings{
    .entry = {repentance_plus::entry::audioPlay, repentance_plus::entry::audioUpdateLoop,
              repentance_plus::entry::roomUpdateAmbience, repentance_plus::entry::musicPlay,
              repentance_plus::entry::musicCrossfade, repentance_plus::entry::roomUpdateMusic},
    .globals = {repentance_plus::globals::game, repentance_plus::globals::manager},
    .layout = {
        repentance_plus::layout::game::room, repentance_plus::layout::game::roomIndex,
        repentance_plus::layout::game::dimension, repentance_plus::layout::manager::music,
        repentance_plus::layout::manager::options, repentance_plus::layout::options::musicVolume,
        repentance_plus::layout::music::currentId, repentance_plus::layout::music::queuedId}};
} // namespace isaac::engine::native_audio

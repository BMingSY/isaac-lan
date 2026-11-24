#pragma once
#include <cstdint>

namespace isaac::engine::native_audio {
struct Bindings {
    struct Entries {
        std::uint32_t sound, updateLoop, roomAmbience, musicPlay, musicFade, roomMusic;
    } entry;
    struct Globals {
        std::uint32_t game, manager;
    } globals;
    struct Layout {
        unsigned room, index, dimension;
        unsigned music, options, musicVolume, currentId, queuedId;
    } layout;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_audio

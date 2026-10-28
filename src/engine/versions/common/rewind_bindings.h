#pragma once
#include <cstdint>

namespace isaac::engine::native_rewind {
struct GameLayout {
    unsigned buffers, selectedBuffer, players, transition;
};
struct PlayerLayout {
    unsigned controller, variant, uses, floorUses;
};
struct BufferLayout {
    unsigned valid, state, stride, door, tick, counters, counterCount;
};
struct TransitionLayout {
    unsigned state, index, direction, animation, dimension;
};
struct Bindings {
    std::uint32_t store, roomTransition, stageTransition, replayTransition, game;
    GameLayout gameLayout;
    PlayerLayout player;
    BufferLayout buffer;
    TransitionLayout transition;
    // Only wrapper side effects that are absent from RoomTransition::Start.
    // Null when the native wrapper has no replay tail; no object is retained.
    void (*finishReplay)(std::uintptr_t game);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_rewind

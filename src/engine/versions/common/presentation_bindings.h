#pragma once
#include "engine/versions/common/player_hud.h"
#include <cstdint>
#include <optional>

namespace isaac::engine::native_presentation {
using Address = std::uintptr_t;
struct Bindings {
    struct Entries {
        unsigned hasCollectible, nightLightQueryReturn, startIntro, updateTransition, setControls;
    } entry;
    unsigned game, manager, logicalWidth, logicalHeight;
    struct Layout {
        unsigned managerScene, playerController;
        struct Game {
            unsigned stage, stageType, roomIndex, dimension, transition, pauseMenu, playerManager;
        } game;
        struct Transition {
            unsigned state, index, dimension;
        } transition;
        struct Room {
            unsigned firstBoss, secondBoss, enemies, delayedEnemies, descriptor;
        } room;
        struct Descriptor {
            unsigned data, flags;
        } descriptor;
        struct Config {
            unsigned stage, type, variant;
        } config;
    } layout;
    // Native object access stays in the version binding. The transition owns
    // its actor reference; adapters must preserve that version's registration.
    void (*prepareActor)(Address image, Address game, Address transition);
    bool (*introMarker)(Address transition);
    bool (*canRestoreControls)(Address game);
    std::optional<native_player_hud::Anchor> (*hudAnchor)(Address image, Address game,
                                                          unsigned index, float width,
                                                          float height);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_presentation

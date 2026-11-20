#pragma once
#include <cstdint>

namespace isaac::engine::native_animation {
struct Bindings {
    struct Entries {
        unsigned render, update, show;
    } entry;
    unsigned game, manager;
    struct Layout {
        unsigned managerScene, nightmare, active, home, stageTransition;
    } layout;
    int gameScene, nightmareScene;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_animation

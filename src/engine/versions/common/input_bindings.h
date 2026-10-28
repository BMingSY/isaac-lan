#pragma once
#include "engine/versions/common/input_query.h"
#include "engine/versions/common/mouse_input.h"
#include <string>

namespace isaac::engine::native_input {
// Values and adapters are private to the selected version backend. Native
// query tokens stay native; only UI requests from the shared API are mapped.
struct Bindings {
    std::uint32_t game, manager, inputManager;
    std::uint32_t pressed, triggered, value, shootingEntity;
    unsigned renderFrame, pauseMenu, players;
    native_mouse::Layout mouse;
    bool (*installQuery)(std::uintptr_t, Detour, Query&, void (*)(const std::string&));
    bool (*installMouse)(std::uintptr_t, native_mouse::Router, native_mouse::Aim&);
    int (*nativeAction)(int);
    void (*resetMenuPrompts)(std::uintptr_t);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_input

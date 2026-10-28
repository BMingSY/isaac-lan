#pragma once
#include <optional>

namespace isaac::engine::native_scene_update {
struct Bindings {
    unsigned update;
    // An inlined update needs a verified continuation after the entire block.
    // A standalone thiscall method simply returns when the update is suppressed.
    std::optional<unsigned> skip;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_scene_update

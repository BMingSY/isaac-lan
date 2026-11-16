#pragma once
#include "engine/versions/common/stage_transition_binding.h"
#include "engine/versions/j835/entrypoints.h"

namespace isaac::engine::j835 {
inline bool installStageTransitionBinding(std::uintptr_t image, const lua::API& api) {
    // J835 also registers the two-argument thunk for a method that consumes
    // three stack arguments. Reuse its native (bool, int, player) adapter.
    return native_stage_binding::install(image, api, entry::luaStageTransitionBinding,
                                         entry::luaPlayerTransitionBinding);
}
} // namespace isaac::engine::j835

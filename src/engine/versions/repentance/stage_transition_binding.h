#pragma once
#include "engine/versions/common/stage_transition_binding.h"
#include "engine/versions/repentance/entrypoints.h"

namespace isaac::engine::repentance {
inline bool installStageTransitionBinding(std::uintptr_t image, const lua::API& api) {
    // Repentance also registers the two-argument thunk for a method that consumes
    // three stack arguments. Reuse its native (bool, int, player) adapter.
    return native_stage_binding::install(image, api, entry::luaStageTransitionBinding,
                                         entry::luaPlayerTransitionBinding);
}
} // namespace isaac::engine::repentance

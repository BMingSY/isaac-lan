#pragma once
#include "engine/versions/common/stage_transition_binding.h"
#include "engine/versions/j460/entrypoints.h"

namespace isaac::engine::j460 {
inline bool installStageTransitionBinding(std::uintptr_t image, const lua::API& api) {
    // Both closures retain their own native method in the same userdata upvalue.
    // StartStageTransition needs the existing (bool, int, EntityPlayer*) thunk;
    // its stock two-argument thunk mismatches the native method's ret 12.
    return native_stage_binding::install(image, api, entry::luaStageTransitionBinding,
                                         entry::luaPlayerTransitionBinding);
}
} // namespace isaac::engine::j460

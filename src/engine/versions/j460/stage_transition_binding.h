#pragma once
#include "engine/lua_api.h"
#include "engine/versions/j460/entrypoints.h"
#include <MinHook.h>
#include <cstdint>

namespace isaac::engine::j460 {
namespace stage_transition_binding {
inline lua::API api;
inline lua::Function adapter;
inline constexpr int playerArgument = 4;
inline int __cdecl invoke(lua_State* state) {
    // The stock adapter accepts nil, but rejects an absent fourth Lua argument.
    if (api.getTop(state) == playerArgument - 1)
        api.setTop(state, playerArgument);
    return adapter(state);
}
} // namespace stage_transition_binding
inline bool installStageTransitionBinding(std::uintptr_t image, const lua::API& api) {
    if (!api.getTop || !api.setTop)
        return false;
    // Both closures retain their own native method in the same userdata upvalue.
    // StartStageTransition needs the existing (bool, int, EntityPlayer*) thunk;
    // its stock two-argument thunk mismatches the native method's ret 12.
    const auto target = reinterpret_cast<void*>(image + entry::luaStageTransitionBinding);
    stage_transition_binding::api = api;
    stage_transition_binding::adapter =
        reinterpret_cast<lua::Function>(image + entry::luaPlayerTransitionBinding);
    return MH_CreateHook(target, reinterpret_cast<void*>(stage_transition_binding::invoke),
                         nullptr) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
} // namespace isaac::engine::j460

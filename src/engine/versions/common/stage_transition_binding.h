#pragma once
#include "engine/lua_api.h"
#include "engine/versions/common/hooks.h"
#include <cstdint>

namespace isaac::engine::native_stage_binding {
inline lua::API api;
inline lua::Function adapter = nullptr;
inline std::uintptr_t installedTarget = 0;
inline constexpr int playerArgument = 4;
inline int __cdecl invoke(lua_State* state) {
    // The stock three-argument adapter accepts nil, but rejects an absent
    // fourth Lua value. Its userdata upvalue still owns the native method.
    if (api.getTop(state) == playerArgument - 1)
        api.setTop(state, playerArgument);
    return adapter(state);
}
inline bool install(std::uintptr_t image, const lua::API& functions, unsigned target,
                    unsigned threeArguments) {
    if (!image || !functions.getTop || !functions.setTop)
        return false;
    const auto replacement = reinterpret_cast<lua::Function>(image + threeArguments);
    if (installedTarget) {
        if (installedTarget != image + target || adapter != replacement)
            return false;
        api = functions;
        return true;
    }
    native_hooks::Group<1> hooks;
    void* original = nullptr;
    api = functions;
    adapter = replacement;
    if (!hooks.add(image + target, invoke, original) || !hooks.enable()) {
        api = {};
        adapter = nullptr;
        return false;
    }
    installedTarget = image + target;
    return true;
}
} // namespace isaac::engine::native_stage_binding

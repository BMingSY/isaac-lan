#pragma once
#include "core/lua_version.h"
#include "engine/imports.h"
#include "engine/profile.h"

namespace isaac::engine {
struct GameLua {
    HMODULE module{};
    lua::Version version{};
};
inline GameLua resolveGameLua(std::uintptr_t image) {
    const auto library = profile().luaModule;
    // REPENTOGON keeps both DLLs loaded. The state creator, stack accessors
    // and destructor imported by the game must agree on the same provider.
    for (auto version : {lua::Version::v53, lua::Version::v54}) {
        const auto module = GetModuleHandleA(version == lua::Version::v53 ? library : "Lua5.4.dll");
        if (!module)
            continue;
        bool matches = true;
        for (const auto name :
             {"lua_newstate", "luaL_newstate", "lua_gettop", "lua_settop", "lua_close"}) {
            const auto slot = imports::find(image, name, library);
            const auto function = GetProcAddress(module, name);
            if (!slot || !function || slot->u1.Function != reinterpret_cast<ULONG_PTR>(function)) {
                matches = false;
                break;
            }
        }
        if (matches)
            return {module, version};
    }
    return {};
}
} // namespace isaac::engine

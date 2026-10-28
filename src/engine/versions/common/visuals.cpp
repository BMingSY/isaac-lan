#include "engine/visuals.h"
#include "engine/lua_api.h"
#include "engine/versions/common/entity_pose.h"
#include "engine/versions/common/entity_visuals.h"
#include "engine/versions/common/grid_state.h"
#include "engine/versions/common/references.h"
#include "engine/versions/common/sprite_state.h"
#include "presentation/ambient_effects.h"

namespace isaac::visuals {
namespace {
isaac::lua::API lua{};
int localAmbientEffect(lua_State* L) {
    lua.pushBoolean(L, presentation::localAmbientEffect(
                           lua.checkInteger(L, 1), lua.checkInteger(L, 2), lua.checkInteger(L, 3)));
    return 1;
}
} // namespace
bool bind(lua_State* L, HMODULE module) {
    const auto image = reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
    if (!lua.load(module, {isaac::lua::Symbol::checkInteger, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}) ||
        !engine::native_sprite::bind(L, module, image) ||
        !engine::native_references::bind(L, module, image) ||
        !engine::native_grid::bind(L, module, image) ||
        !engine::native_entity_pose::bind(L, module) ||
        !engine::native_visuals::bind(L, module, image))
        return false;
    lua.pushClosure(L, localAmbientEffect, 0);
    lua.setField(L, -2, "presentation_local_effect");
    return true;
}
} // namespace isaac::visuals

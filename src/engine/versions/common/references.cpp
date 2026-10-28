#include "engine/versions/common/references.h"
#include "engine/versions/common/references_bindings.h"
#include "engine/lua_api.h"
#include "runtime/session.h"
namespace isaac::engine::native_references {
namespace {
using Address = std::uintptr_t;
Address image = 0;
isaac::lua::API lua{};
Address entitySprite(lua_State* L, int index) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, index));
    if (!sample || lua.rawLength(L, index) != 8 || sample[1] < bindings.sprite)
        throw std::runtime_error("Invalid entity Sprite wrapper");
    return sample[1] - bindings.sprite;
}
int entityMinecart(lua_State* L) {
    try {
        const auto entity = entitySprite(L, 1);
        if (lua.getTop(L) == 1) {
            lua.pushInteger(L, native_entity_links::index(entity, bindings.entities));
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas restore minecart links");
        const auto cart = lua.type(L, 2) == 1 && !lua.toBoolean(L, 2) ? 0 : entitySprite(L, 2);
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        native_entity_links::restore(entity, bindings.entities, cart,
                                     reinterpret_cast<Assign>(image + bindings.assign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int actorHeldEntity(lua_State* L) {
    try {
        const auto player = entitySprite(L, 1);
        if (lua.getTop(L) == 1) {
            lua.pushInteger(L, native_entity_links::heldIndex(player, bindings.entities));
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas restore player held entity links");
        const auto held = lua.type(L, 2) == 1 && !lua.toBoolean(L, 2) ? 0 : entitySprite(L, 2);
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        native_entity_links::restoreHeld(player, bindings.entities, held,
                                         reinterpret_cast<Assign>(image + bindings.assign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int bossHeldBombs(lua_State* L) {
    try {
        const auto entity = entitySprite(L, 1);
        const auto count = native_held_bombs::slotCount(entity, bindings.bombs);
        if (lua.getTop(L) == 1) {
            const auto indices = native_held_bombs::indices(entity, bindings.bombs);
            for (unsigned i = 0; i < count; ++i)
                lua.pushInteger(L, indices[i]);
            return count;
        }
        if (!runtime::replica() || lua.getTop(L) != static_cast<int>(count + 1))
            throw std::runtime_error("Only replicas restore Boss held bombs");
        std::array<Address, 3> bombs{};
        for (unsigned i = 0; i < count; ++i)
            if (lua.type(L, i + 2) != 1 || lua.toBoolean(L, i + 2))
                bombs[i] = entitySprite(L, i + 2);
        using Resize = void(__attribute__((thiscall))*)(void*, unsigned);
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        native_held_bombs::restore(entity, bindings.bombs, bombs,
                                   reinterpret_cast<Resize>(image + bindings.resize),
                                   reinterpret_cast<Assign>(image + bindings.assign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
bool bind(lua_State* L, HMODULE module, Address base) {
    if (!base || !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::type,
                                    isaac::lua::Symbol::toBoolean, isaac::lua::Symbol::toUserdata,
                                    isaac::lua::Symbol::rawLength, isaac::lua::Symbol::pushInteger,
                                    isaac::lua::Symbol::pushBoolean,
                                    isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}))
        return false;
    image = base;
    lua.pushClosure(L, entityMinecart, 0);
    lua.setField(L, -2, "entity_minecart");
    lua.pushClosure(L, actorHeldEntity, 0);
    lua.setField(L, -2, "actor_held_entity");
    lua.pushClosure(L, bossHeldBombs, 0);
    lua.setField(L, -2, "boss_held_bombs");
    return true;
}
} // namespace isaac::engine::native_references

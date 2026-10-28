#include "engine/versions/common/grid_state.h"
#include "engine/versions/common/grid_state_bindings.h"
#include "engine/lua_api.h"
#include "runtime/session.h"
#include <limits>

namespace isaac::engine::native_grid {
namespace {
using Address = std::uintptr_t;
isaac::lua::API lua{};
Address image = 0;
template <class T> T& at(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
Address room() {
    const auto game = image ? at<Address>(image, bindings.gameGlobal) : 0;
    const auto result = game ? at<Address>(game, bindings.gameRoom) : 0;
    if (!result)
        throw std::runtime_error("Missing native grid room");
    return result;
}
Address grid(lua_State* L, int index) {
    const auto wrapper = static_cast<const Address*>(lua.toUserdata(L, index));
    if (!wrapper || lua.rawLength(L, index) != 8 || wrapper[1] <= bindings.grid.sprite)
        throw std::runtime_error("Grid state requires a borrowed grid Sprite");
    const auto result = wrapper[1] - bindings.grid.sprite;
    if (!at<unsigned>(result, bindings.grid.type))
        throw std::runtime_error("Grid state requires an initialized grid");
    return result;
}
void requireReplica() {
    if (!runtime::replica())
        throw std::runtime_error("Only replicas restore grid state");
}
int roomRails(lua_State* L) {
    try {
        const auto target = room();
        if (!lua.getTop(L)) {
            const auto value = native_rails::grid(target, bindings.rails);
            lua.pushLString(L, reinterpret_cast<const char*>(value.data()), value.size());
            return 1;
        }
        requireReplica();
        if (lua.getTop(L) != 1)
            throw std::runtime_error("Invalid room rails arguments");
        std::size_t size = 0;
        const auto data = lua.checkString(L, 1, &size);
        native_rails::restore(target, bindings.rails,
                              {reinterpret_cast<const std::uint8_t*>(data), size});
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int doorSprite(lua_State* L) {
    try {
        if (lua.getTop(L) != 1)
            throw std::runtime_error("Invalid door Sprite arguments");
        const auto object = grid(L, 1);
        if (at<unsigned>(object, bindings.grid.type) != doorType)
            throw std::runtime_error("Extra Sprite requires a door");
        const auto source = static_cast<const Address*>(lua.toUserdata(L, 1));
        const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
        wrapper[0] = source[0];
        wrapper[1] = object + bindings.grid.extraSprite;
        lua.getMetatable(L, 1);
        lua.setMetatable(L, -2);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int gridVariant(lua_State* L) {
    try {
        requireReplica();
        if (lua.getTop(L) != 2)
            throw std::runtime_error("Invalid grid variant arguments");
        const auto target = grid(L, 1);
        const auto value = lua.checkInteger(L, 2);
        if (value < (std::numeric_limits<int>::min)() || value > (std::numeric_limits<int>::max)())
            throw std::runtime_error("Invalid grid variant");
        at<int>(target, bindings.grid.variant) = static_cast<int>(value);
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int removeGrid(lua_State* L) {
    try {
        requireReplica();
        const auto index = lua.checkInteger(L, 1);
        if (lua.getTop(L) != 1 || index < 0 || index >= native_rails::count)
            throw std::runtime_error("Invalid grid removal index");
        const auto target = room();
        using Remove = void(__attribute__((thiscall))*)(void*, int, int, bool);
        // Deferred Lua removal would delete a replacement in the next update.
        reinterpret_cast<Remove>(image + bindings.removeImmediate)(
            reinterpret_cast<void*>(target), static_cast<int>(index), 0, false);
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int doorSlot(lua_State* L) {
    try {
        requireReplica();
        const auto target = room();
        const auto slot = lua.checkInteger(L, 1);
        if (slot == -1) {
            if (lua.getTop(L) != 1)
                throw std::runtime_error("Invalid door detach arguments");
            for (unsigned i = 0; i < doorSlots; ++i)
                at<Address>(target, bindings.room.doors + i * sizeof(Address)) = 0;
            lua.pushBoolean(L, true);
            return 1;
        }
        const auto index = lua.checkInteger(L, 2);
        if (slot < 0 || slot >= doorSlots || index < 0 || index >= native_rails::count ||
            (lua.getTop(L) != 2 && lua.getTop(L) != 3))
            throw std::runtime_error("Invalid door slot or grid index");
        if (lua.getTop(L) == 3) {
            const auto door = grid(L, 3);
            if (at<unsigned>(door, bindings.grid.type) != doorType ||
                at<unsigned>(door, bindings.grid.index) != static_cast<unsigned>(index) ||
                at<Address>(target, bindings.room.cells + index * sizeof(Address)) != door)
                throw std::runtime_error("Door is not owned by the current room grid");
            // The cell owns the allocation; the door table only borrows it.
            at<unsigned>(target, bindings.room.indices + slot * sizeof(unsigned)) =
                static_cast<unsigned>(index);
            at<Address>(target, bindings.room.doors + slot * sizeof(Address)) = door;
            lua.pushBoolean(L, true);
            return 1;
        }
        auto& destination = at<unsigned>(target, bindings.room.indices + slot * sizeof(unsigned));
        struct Destination {
            unsigned& value;
            unsigned previous;
            bool committed = false;
            ~Destination() {
                if (!committed)
                    value = previous;
            }
        } transaction{destination, destination};
        destination = static_cast<unsigned>(index);
        using Make = bool(__attribute__((thiscall))*)(void*, int);
        transaction.committed = reinterpret_cast<Make>(image + bindings.makeDoor)(
            reinterpret_cast<void*>(target), static_cast<int>(slot));
        lua.pushBoolean(L, transaction.committed);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
bool bind(lua_State* L, HMODULE module, Address base) {
    if (!base ||
        !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::newUserdata,
                           isaac::lua::Symbol::getMetatable, isaac::lua::Symbol::setMetatable,
                           isaac::lua::Symbol::checkInteger, isaac::lua::Symbol::checkString,
                           isaac::lua::Symbol::pushLString, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}))
        return false;
    image = base;
    lua.pushClosure(L, roomRails, 0);
    lua.setField(L, -2, "room_rails");
    lua.pushClosure(L, gridVariant, 0);
    lua.setField(L, -2, "grid_variant");
    lua.pushClosure(L, removeGrid, 0);
    lua.setField(L, -2, "grid_remove");
    lua.pushClosure(L, doorSprite, 0);
    lua.setField(L, -2, "door_sprite");
    lua.pushClosure(L, doorSlot, 0);
    lua.setField(L, -2, "door_slot");
    return true;
}
} // namespace isaac::engine::native_grid

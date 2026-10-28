#include "engine/lua_api.h"
#include "engine/versions/common/entity_pose.h"
#include "engine/versions/common/sprite_state.h"
#include "engine/versions/j460/layout.h"
#include "engine/visuals.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include "presentation/ambient_effects.h"
#include <array>
#include <bit>
#include <cmath>
#include <cstring>
#include <vector>

#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/entity_links.h"
#include "engine/versions/j460/held_bombs.h"
#include "engine/versions/j460/rails.h"
namespace j460 = isaac::engine::j460;

namespace isaac::visuals {
namespace {
using Address = std::uintptr_t;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
isaac::lua::API lua{};
int roomRails(lua_State* L) {
    try {
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        const auto game = at<Address>(image, j460::globals::game);
        const auto room = game ? at<Address>(game, 0x18300) : 0;
        if (!lua.getTop(L)) {
            const auto value = j460::rails::grid(room);
            lua.pushLString(L, reinterpret_cast<const char*>(value.data()), value.size());
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 1)
            throw std::runtime_error("Only replicas restore room rails");
        std::size_t size = 0;
        const auto data = lua.checkString(L, 1, &size);
        j460::rails::restore(room, {reinterpret_cast<const std::uint8_t*>(data), size});
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
Address entitySprite(lua_State* L, int index) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, index));
    if (!sample || lua.rawLength(L, index) != 8 || sample[1] < 0x48)
        throw std::runtime_error("Invalid entity Sprite wrapper");
    return sample[1] - 0x48;
}
int entityMinecart(lua_State* L) {
    try {
        const auto entity = entitySprite(L, 1);
        if (lua.getTop(L) == 1) {
            lua.pushInteger(L, j460::entity_links::index(entity));
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas restore minecart links");
        const auto cart = lua.type(L, 2) == 1 && !lua.toBoolean(L, 2) ? 0 : entitySprite(L, 2);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        j460::entity_links::restore(entity, cart,
                                    reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign));
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
            lua.pushInteger(L, j460::entity_links::heldIndex(player));
            return 1;
        }
        if (!runtime::replica() || lua.getTop(L) != 2)
            throw std::runtime_error("Only replicas restore player held entity links");
        const auto held = lua.type(L, 2) == 1 && !lua.toBoolean(L, 2) ? 0 : entitySprite(L, 2);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        j460::entity_links::restoreHeld(
            player, held, reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign));
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
        const auto count = j460::held_bombs::slotCount(entity);
        if (lua.getTop(L) == 1) {
            const auto indices = j460::held_bombs::indices(entity);
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
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        using Resize = void(__attribute__((thiscall))*)(void*, unsigned);
        using Assign = void(__attribute__((fastcall))*)(void*, void*);
        j460::held_bombs::restore(
            entity, bombs, reinterpret_cast<Resize>(image + j460::entry::bossHeldBombsResize),
            reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign));
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int prepareEntity(lua_State* L) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    if (runtime::replica() || !sample || lua.rawLength(L, 1) != 8 || sample[1] < 0x48) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto entity = sample[1] - 0x48;
    if (at<unsigned>(entity, 0x28) == 881) {
        using Prepare = void(__attribute__((thiscall))*)(void*);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        // Background authoritative rooms never render in the host viewport.
        // Compute their Needle body layer poses before capturing the sprite.
        reinterpret_cast<Prepare>(image + j460::entry::nPCNeedlePrepareVisual)(
            reinterpret_cast<void*>(entity));
    }
    lua.pushBoolean(L, true);
    return 1;
}
int localAmbientEffect(lua_State* L) {
    // Share one portable classification with the replica update hook. This
    // query accepts ordinary IDs and never borrows or changes a game object.
    lua.pushBoolean(L, presentation::localAmbientEffect(
                           lua.checkInteger(L, 1), lua.checkInteger(L, 2), lua.checkInteger(L, 3)));
    return 1;
}
int doorSprite(lua_State* L) {
    // ExtraSprite's Lua property returns an owning copy in J460. Expose the
    // door-owned ANM2 through the same non-owning wrapper as GetSprite().
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!sample || lua.rawLength(L, 1) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
    wrapper[0] = sample[0];
    wrapper[1] = sample[1] - 0x40 + 0x27c;
    lua.getMetatable(L, 1);
    lua.setMetatable(L, -2);
    return 1;
}
int gridVariant(lua_State* L) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!runtime::replica() || !sample || lua.rawLength(L, 1) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    at<int>(sample[1] - 0x40, 8) = static_cast<int>(lua.checkInteger(L, 2));
    lua.pushBoolean(L, true);
    return 1;
}
int removeGrid(lua_State* L) {
    const auto index = lua.checkInteger(L, 1);
    if (!runtime::replica() || index < 0 || index >= 448) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
    const auto room = at<Address>(at<Address>(image, j460::globals::game), 0x18300);
    using Remove = void(__attribute__((thiscall))*)(void*, int, int, bool);
    // Lua RemoveGridEntity queues removal for a later Room::Update. That
    // pending index would delete a replacement installed by this snapshot.
    reinterpret_cast<Remove>(image + j460::entry::roomRemoveGridEntityImmediate)(
        reinterpret_cast<void*>(room), static_cast<int>(index), 0, false);
    lua.pushBoolean(L, true);
    return 1;
}
int doorSlot(lua_State* L) {
    if (!runtime::replica()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
    const auto room = at<Address>(at<Address>(image, j460::globals::game), 0x18300);
    const auto slot = lua.checkInteger(L, 1);
    if (slot == -1) {
        for (unsigned i = 0; i < 8; ++i)
            at<Address>(room, 0x724 + i * 4) = 0;
    } else {
        const auto index = lua.checkInteger(L, 2);
        if (slot < 0 || slot > 7 || index < 0 || index >= 448) {
            lua.pushBoolean(L, false);
            return 1;
        }
        at<unsigned>(room, 0x744 + slot * 4) = static_cast<unsigned>(index);
        if (lua.getTop(L) < 3) {
            using MakeDoor = bool(__attribute__((thiscall))*)(void*, int);
            lua.pushBoolean(L, reinterpret_cast<MakeDoor>(image + j460::entry::roomMakeDoor)(
                                   reinterpret_cast<void*>(room), static_cast<int>(slot)));
            return 1;
        }
        auto sample = static_cast<Address*>(lua.toUserdata(L, 3));
        if (!sample || lua.rawLength(L, 3) != 8) {
            lua.pushBoolean(L, false);
            return 1;
        }
        // The room grid vector owns the door; Room::GetDoor/Render use a
        // separate borrowed slot table. Late Devil/Angel doors need both.
        at<Address>(room, 0x724 + slot * 4) = sample[1] - 0x40;
    }
    lua.pushBoolean(L, true);
    return 1;
}
unsigned number(lan::Reader& r) {
    const auto bits = r.u32();
    if (!std::isfinite(std::bit_cast<float>(bits)))
        throw std::runtime_error("Invalid visual number");
    return bits;
}
Address layer(Address s, unsigned id) {
    return engine::native_sprite::findLayer(s, id);
}
int familiarBody(lua_State* L) {
    try {
        namespace body = j460::layout::familiarBody;
        const auto familiar = entitySprite(L, 1);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        if (at<unsigned>(familiar, j460::layout::entity::type) != 3)
            throw std::runtime_error("Body sprites require a familiar");
        const auto data = at<Address>(familiar, body::extraData);
        if (!data || at<Address>(data, 0) != image + body::dataVtable) {
            lua.pushBoolean(L, false);
            return 1;
        }
        if (lua.getTop(L) != 1) {
            if (!runtime::replica() || lua.getTop(L) != 2)
                throw std::runtime_error("Only replicas restore familiar body layers");
            std::size_t size = 0;
            const auto bytes = lua.checkString(L, 2, &size);
            lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
            std::array<int, body::layerCount> layers{};
            for (unsigned i = 0; i < layers.size(); ++i) {
                layers[i] = std::bit_cast<int>(r.u32());
                const auto s = data + body::sprites + (i + 1) * j460::layout::sprite::size;
                if (layers[i] < -1 || (layers[i] >= 0 && !layer(s, layers[i])))
                    throw std::runtime_error("Invalid familiar body layer");
            }
            r.finish();
            for (unsigned i = 0; i < layers.size(); ++i)
                at<int>(data, body::layers + i * sizeof(int)) = layers[i];
            lua.pushBoolean(L, true);
            return 1;
        }
        lan::Writer w(lan::Message::world);
        for (unsigned i = 0; i < body::layerCount; ++i)
            w.u32(at<unsigned>(data, body::layers + i * sizeof(int)));
        lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
        lua.createTable(L, body::spriteCount, 0);
        const auto source = static_cast<Address*>(lua.toUserdata(L, 1));
        for (unsigned i = 0; i < body::spriteCount; ++i) {
            const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
            wrapper[0] = source[0];
            wrapper[1] = data + body::sprites + i * j460::layout::sprite::size;
            lua.getMetatable(L, 1);
            lua.setMetatable(L, -2);
            lua.rawSetI(L, -2, i + 1);
        }
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int familiarTether(lua_State* L) {
    try {
        namespace tether = j460::layout::tether;
        const auto familiar = entitySprite(L, 1);
        const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
        if (at<unsigned>(familiar, j460::layout::entity::type) != 3)
            throw std::runtime_error("Tether capture requires a familiar");
        const auto data = at<Address>(familiar, tether::extraData);
        if (!data || at<Address>(data, 0) != image + tether::dataVtable) {
            lua.pushBoolean(L, false);
            return 1;
        }
        const auto count = at<unsigned>(data, tether::count);
        const auto capacity = at<unsigned>(data, tether::capacity);
        const auto first = at<unsigned>(data, tether::first);
        if (count > tether::maxPoints || count > capacity || capacity > 4096 ||
            (count && (!capacity || (capacity & (capacity - 1)))))
            throw std::runtime_error("Invalid native tether points");
        lan::Writer w(lan::Message::world);
        w.u16(count);
        const auto points = at<Address>(data, tether::points);
        for (unsigned i = 0; i < count; ++i) {
            const auto point =
                at<Address>(points, ((first + i) & (capacity - 1)) * sizeof(Address));
            for (unsigned axis = 0; axis < 3; ++axis) {
                const auto value = at<float>(point, axis * sizeof(float));
                if (!std::isfinite(value))
                    throw std::runtime_error("Invalid tether coordinate");
                w.u32(std::bit_cast<unsigned>(value));
            }
        }
        lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
        const auto source = static_cast<Address*>(lua.toUserdata(L, 1));
        const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
        wrapper[0] = source[0];
        wrapper[1] = data + tether::sprite;
        lua.getMetatable(L, 1);
        lua.setMetatable(L, -2);
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int renderTether(lua_State* L) {
    try {
        namespace tether = j460::layout::tether;
        if (!runtime::replica())
            throw std::runtime_error("Only replicas draw tether snapshots");
        const auto familiar = entitySprite(L, 1);
        if (at<unsigned>(familiar, j460::layout::entity::type) != 3)
            throw std::runtime_error("Tether rendering requires a familiar");
        const auto spriteSize = lua.rawLength(L, 2);
        const auto spriteWrapper = static_cast<const Address*>(lua.toUserdata(L, 2));
        if (!spriteWrapper || (spriteSize != 8 && spriteSize != j460::layout::sprite::size + 8))
            throw std::runtime_error("Invalid tether Sprite");
        std::size_t length = 0;
        const auto bytes = lua.checkString(L, 3, &length);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), length});
        const auto count = r.u16();
        if (count > tether::maxPoints)
            throw std::runtime_error("Too many tether points");
        std::array<std::array<float, 3>, tether::maxPoints> points{};
        std::array<Address, tether::maxPoints> map{};
        for (unsigned i = 0; i < count; ++i) {
            for (auto& axis : points[i])
                axis = std::bit_cast<float>(number(r));
            map[i] = reinterpret_cast<Address>(points[i].data());
        }
        r.finish();
        if (count > 1) {
            const auto image = reinterpret_cast<Address>(GetModuleHandleW(nullptr));
            alignas(Address) std::array<std::byte, tether::size> storage{};
            const auto data = reinterpret_cast<Address>(storage.data());
            at<Address>(data, 0) = image + tether::dataVtable;
            at<Address>(data, tether::points) = reinterpret_cast<Address>(map.data());
            at<unsigned>(data, tether::capacity) = tether::maxPoints;
            at<unsigned>(data, tether::count) = count;
            // The render routine only borrows this ANM2 and point deque. Neither
            // the stack view nor its shallow Sprite copy is ever destroyed as
            // a native owner, and no update/weapon gameplay is invoked.
            std::memcpy(storage.data() + tether::sprite, reinterpret_cast<void*>(spriteWrapper[1]),
                        j460::layout::sprite::size);
            struct Borrow {
                Address& target;
                Address saved;
                ~Borrow() {
                    target = saved;
                }
            } borrow{at<Address>(familiar, tether::extraData),
                     at<Address>(familiar, tether::extraData)};
            borrow.target = data;
            const std::array<float, 2> offset{};
            using Render = void(__attribute__((thiscall))*)(void*, const void*, int);
            reinterpret_cast<Render>(image + j460::entry::familiarRenderTether)(
                reinterpret_cast<void*>(familiar), offset.data(), 0);
        }
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}

} // namespace
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::type,
                           isaac::lua::Symbol::toBoolean, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::newUserdata,
                           isaac::lua::Symbol::getMetatable, isaac::lua::Symbol::setMetatable,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::pushInteger, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::rawSetI, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField}))
        return false;
    if (!engine::native_sprite::bind(L, module,
                                     reinterpret_cast<Address>(GetModuleHandleW(nullptr))))
        return false;
    lua.pushClosure(L, bossHeldBombs, 0);
    lua.setField(L, -2, "boss_held_bombs");
    lua.pushClosure(L, entityMinecart, 0);
    lua.setField(L, -2, "entity_minecart");
    lua.pushClosure(L, actorHeldEntity, 0);
    lua.setField(L, -2, "actor_held_entity");
    lua.pushClosure(L, roomRails, 0);
    lua.setField(L, -2, "room_rails");
    if (!engine::native_entity_pose::bind(L, module))
        return false;
    lua.pushClosure(L, familiarTether, 0);
    lua.setField(L, -2, "familiar_tether");
    lua.pushClosure(L, familiarBody, 0);
    lua.setField(L, -2, "familiar_body");
    lua.pushClosure(L, renderTether, 0);
    lua.setField(L, -2, "familiar_tether_render");

    lua.pushClosure(L, prepareEntity, 0);
    lua.setField(L, -2, "entity_prepare");
    lua.pushClosure(L, localAmbientEffect, 0);
    lua.setField(L, -2, "presentation_local_effect");
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
} // namespace isaac::visuals

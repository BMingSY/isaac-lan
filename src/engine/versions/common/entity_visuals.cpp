#include "engine/versions/common/entity_visuals.h"
#include "engine/versions/common/entity_visuals_bindings.h"
#include "engine/versions/common/sprite_state.h"
#include "engine/lua_api.h"
#include "compat/game_ids.h"
#include "net/protocol.h"
#include "runtime/session.h"
#include <array>
#include <bit>
#include <cmath>
#include <cstring>

namespace isaac::engine::native_visuals {
namespace {
using Address = std::uintptr_t;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
isaac::lua::API lua{};
Address image = 0;
Address entitySprite(lua_State* L, int index) {
    auto sample = static_cast<Address*>(lua.toUserdata(L, index));
    if (!sample || lua.rawLength(L, index) != 8 || sample[1] <= bindings.entitySprite)
        throw std::runtime_error("Invalid entity Sprite wrapper");
    return sample[1] - bindings.entitySprite;
}
int pickupFlipVisual(lua_State* L) {
    try {
        if (!bindings.flipSprite)
            throw std::runtime_error("Flip visual binding is unavailable");
        const auto entity = entitySprite(L, 1);
        if (at<unsigned>(entity, bindings.entityType) != 5 ||
            at<unsigned>(entity, bindings.entityVariant) != 100)
            throw std::runtime_error("Flip visual requires a collectible pedestal");
        if (lua.getTop(L) != 1) {
            if (!runtime::replica() || lua.getTop(L) != 2 || lua.type(L, 2) != 1)
                throw std::runtime_error("Only replicas restore Flip visibility");
            at<bool>(entity, bindings.flipVisible) = lua.toBoolean(L, 2);
            lua.pushBoolean(L, true);
            return 1;
        }
        lua.pushBoolean(L, at<bool>(entity, bindings.flipVisible));
        const auto source = static_cast<Address*>(lua.toUserdata(L, 1));
        const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
        wrapper[0] = source[0];
        wrapper[1] = entity + bindings.flipSprite;
        lua.getMetatable(L, 1);
        lua.setMetatable(L, -2);
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int prepareEntity(lua_State* L) {
    try {
        if (runtime::replica() || lua.getTop(L) != 1)
            throw std::runtime_error("Only authority prepares entity presentation");
        const auto entity = entitySprite(L, 1);
        if (at<unsigned>(entity, bindings.entityType) == compat::ids::entity::needle) {
            using Prepare = void(__attribute__((thiscall))*)(void*);
            // Background authoritative rooms never render in the host viewport.
            // Compute Needle body poses without running NPC AI.
            reinterpret_cast<Prepare>(image +
                                      bindings.prepareNeedle)(reinterpret_cast<void*>(entity));
        }
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
unsigned number(lan::Reader& r) {
    const auto bits = r.u32();
    if (!std::isfinite(std::bit_cast<float>(bits)))
        throw std::runtime_error("Invalid visual number");
    return bits;
}
Address layer(Address s, unsigned id) {
    return native_sprite::findLayer(s, id);
}
int familiarBody(lua_State* L) {
    try {
        const auto& body = bindings.body;
        const auto familiar = entitySprite(L, 1);
        if (at<unsigned>(familiar, bindings.entityType) != compat::ids::entity::familiar)
            throw std::runtime_error("Body sprites require a familiar");
        const auto data = at<Address>(familiar, bindings.extraData);
        if (!data || at<Address>(data, 0) != image + body.dataVtable) {
            lua.pushBoolean(L, false);
            return 1;
        }
        if (lua.getTop(L) != 1) {
            if (!runtime::replica() || lua.getTop(L) != 2)
                throw std::runtime_error("Only replicas restore familiar body layers");
            std::size_t size = 0;
            const auto bytes = lua.checkString(L, 2, &size);
            lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
            std::array<int, bodyLayers> layers{};
            for (unsigned i = 0; i < layers.size(); ++i) {
                layers[i] = std::bit_cast<int>(r.u32());
                const auto s = data + body.sprites + (i + 1) * bindings.spriteSize;
                if (layers[i] < -1 || (layers[i] >= 0 && !layer(s, layers[i])))
                    throw std::runtime_error("Invalid familiar body layer");
            }
            r.finish();
            for (unsigned i = 0; i < layers.size(); ++i)
                at<int>(data, body.layers + i * sizeof(int)) = layers[i];
            lua.pushBoolean(L, true);
            return 1;
        }
        lan::Writer w(lan::Message::world);
        for (unsigned i = 0; i < bodyLayers; ++i)
            w.u32(at<unsigned>(data, body.layers + i * sizeof(int)));
        lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1);
        lua.createTable(L, bodySprites, 0);
        const auto source = static_cast<Address*>(lua.toUserdata(L, 1));
        for (unsigned i = 0; i < bodySprites; ++i) {
            const auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
            wrapper[0] = source[0];
            wrapper[1] = data + body.sprites + i * bindings.spriteSize;
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
        const auto& tether = bindings.tether;
        if (lua.getTop(L) != 1)
            throw std::runtime_error("Tether capture expects one familiar");
        const auto familiar = entitySprite(L, 1);
        if (at<unsigned>(familiar, bindings.entityType) != compat::ids::entity::familiar)
            throw std::runtime_error("Tether capture requires a familiar");
        const auto data = at<Address>(familiar, bindings.extraData);
        if (!data || at<Address>(data, 0) != image + tether.dataVtable) {
            lua.pushBoolean(L, false);
            return 1;
        }
        const auto count = at<unsigned>(data, tether.count);
        const auto capacity = at<unsigned>(data, tether.capacity);
        const auto first = at<unsigned>(data, tether.first);
        if (count > maxTetherPoints || count > capacity || capacity > maxTetherCapacity ||
            (capacity && (capacity & (capacity - 1))))
            throw std::runtime_error("Invalid native tether points");
        lan::Writer w(lan::Message::world);
        w.u16(count);
        const auto points = at<Address>(data, tether.points);
        if (count && !points)
            throw std::runtime_error("Missing native tether map");
        for (unsigned i = 0; i < count; ++i) {
            const auto point =
                at<Address>(points, ((first + i) & (capacity - 1)) * sizeof(Address));
            if (!point)
                throw std::runtime_error("Missing native tether point");
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
        wrapper[1] = data + tether.sprite;
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
        const auto& tether = bindings.tether;
        if (!runtime::replica() || lua.getTop(L) != 3)
            throw std::runtime_error("Only replicas draw tether snapshots");
        const auto familiar = entitySprite(L, 1);
        if (at<unsigned>(familiar, bindings.entityType) != compat::ids::entity::familiar)
            throw std::runtime_error("Tether rendering requires a familiar");
        const auto spriteSize = lua.rawLength(L, 2);
        const auto spriteWrapper = static_cast<const Address*>(lua.toUserdata(L, 2));
        if (!spriteWrapper || (spriteSize != 8 && spriteSize != bindings.spriteSize + 8) ||
            !spriteWrapper[1])
            throw std::runtime_error("Invalid tether Sprite");
        std::size_t length = 0;
        const auto bytes = lua.checkString(L, 3, &length);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), length});
        const auto count = r.u16();
        if (count > maxTetherPoints)
            throw std::runtime_error("Too many tether points");
        std::array<std::array<float, 3>, maxTetherPoints> points{};
        std::array<Address, maxTetherPoints> map{};
        for (unsigned i = 0; i < count; ++i) {
            for (auto& axis : points[i])
                axis = std::bit_cast<float>(number(r));
            map[i] = reinterpret_cast<Address>(points[i].data());
        }
        r.finish();
        if (count > 1) {
            alignas(Address) std::array<std::byte, maxTetherDataBytes> storage{};
            const auto data = reinterpret_cast<Address>(storage.data());
            at<Address>(data, 0) = image + tether.dataVtable;
            at<Address>(data, tether.points) = reinterpret_cast<Address>(map.data());
            at<unsigned>(data, tether.capacity) = maxTetherPoints;
            at<unsigned>(data, tether.count) = count;
            // The render routine only borrows this ANM2 and point deque. Neither
            // the stack view nor its shallow Sprite copy is ever destroyed as
            // a native owner, and no update/weapon gameplay is invoked.
            std::memcpy(storage.data() + tether.sprite, reinterpret_cast<void*>(spriteWrapper[1]),
                        bindings.spriteSize);
            struct Borrow {
                Address& target;
                Address saved;
                ~Borrow() {
                    target = saved;
                }
            } borrow{at<Address>(familiar, bindings.extraData),
                     at<Address>(familiar, bindings.extraData)};
            borrow.target = data;
            const std::array<float, 2> offset{};
            using Render = void(__attribute__((thiscall))*)(void*, const void*, int);
            reinterpret_cast<Render>(image + bindings.renderTether)(
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
bool bind(lua_State* L, HMODULE module, Address base) {
    if (!base || bindings.tether.size > maxTetherDataBytes ||
        bindings.tether.sprite + bindings.spriteSize > bindings.tether.size ||
        !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::type,
                           isaac::lua::Symbol::toBoolean, isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::rawLength, isaac::lua::Symbol::newUserdata,
                           isaac::lua::Symbol::getMetatable, isaac::lua::Symbol::setMetatable,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::rawSetI, isaac::lua::Symbol::pushClosure,
                           isaac::lua::Symbol::setField}))
        return false;
    image = base;
    lua.pushClosure(L, familiarTether, 0);
    lua.setField(L, -2, "familiar_tether");
    lua.pushClosure(L, familiarBody, 0);
    lua.setField(L, -2, "familiar_body");
    lua.pushClosure(L, renderTether, 0);
    lua.setField(L, -2, "familiar_tether_render");
    lua.pushClosure(L, prepareEntity, 0);
    lua.setField(L, -2, "entity_prepare");
    lua.pushClosure(L, pickupFlipVisual, 0);
    lua.setField(L, -2, "pickup_flip_visual");
    return true;
}
} // namespace isaac::engine::native_visuals

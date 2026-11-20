#include "engine/versions/common/actor_state.h"
#include "engine/versions/common/actor_state_bindings.h"
#include "engine/lua_api.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include "compat/items/crafting_bag.h"
#include "compat/game_ids.h"
#include "core/poop_state.h"
#include <algorithm>
#include <array>
#include <stdexcept>
namespace isaac::engine::native_actor_state {
namespace {
using Address = std::uintptr_t;
constexpr unsigned pocketSlots = 4, pocketStride = 8, chargeSprites = 7, hudSlots = 8;
constexpr unsigned maxCostumes = 4096;
Address image = 0;
Callbacks context;
isaac::lua::API lua;
struct Vector {
    Address begin, end, capacity;
};
template <class T> T& at(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
template <class T> T engine(unsigned rva) {
    return reinterpret_cast<T>(image + rva);
}
Address game() {
    return image ? at<Address>(image, bindings.game) : 0;
}
int actorSprites(lua_State* L) {
    const auto index = lua.checkInteger(L, 1);
    const auto all = context.roster(false);
    auto sample = static_cast<Address*>(lua.toUserdata(L, 2));
    if (index < 0 || static_cast<std::size_t>(index) >= all.size() || !sample ||
        lua.rawLength(L, 2) != 8 || !all[index] ||
        sample[1] != all[index] + bindings.entity.sprite) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto player = all[index];
    const auto costumes = at<Vector>(player, bindings.player.costumes);
    if (costumes.end < costumes.begin || costumes.end > costumes.capacity ||
        (costumes.end && !costumes.begin) ||
        (costumes.end - costumes.begin) % bindings.player.costumeStride ||
        costumes.end - costumes.begin > bindings.player.costumeStride * maxCostumes) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lua.createTable(L,
                    bindings.player.sprites.size() + chargeSprites +
                        (costumes.end - costumes.begin) / bindings.player.costumeStride,
                    0);
    unsigned ordinal = 1;
    auto push = [&](Address sprite) {
        // Clone the game's non-owning LuaBridge Sprite wrapper, retaining its
        // native metatable/destructor. The ANM2 remains owned by the player.
        auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
        wrapper[0] = sample[0];
        wrapper[1] = sprite;
        lua.getMetatable(L, 2);
        lua.setMetatable(L, -2);
        lua.rawSetI(L, -2, ordinal++);
    };
    for (auto offset : bindings.player.sprites)
        push(player + offset);
    // The seven native charge-bar sprites advance in Player::Update, which
    // replicas suppress. Their charged/flash overlays must follow the host.
    for (unsigned i = 0; i < chargeSprites; ++i)
        push(player + bindings.player.chargeSprites + i * bindings.player.spriteStride);
    for (auto address = costumes.begin; address < costumes.end;
         address += bindings.player.costumeStride)
        push(address);
    return 1;
}
int actorPockets(lua_State* L) {
    try {
        auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
        if (!wrapper || lua.rawLength(L, 1) != 8 || wrapper[1] <= bindings.entity.sprite)
            throw std::runtime_error("Invalid actor pocket wrapper");
        const auto player = wrapper[1] - bindings.entity.sprite;
        const auto all = context.roster(true);
        if (std::find(all.begin(), all.end(), player) == all.end() ||
            at<unsigned>(player, bindings.entity.type) != compat::ids::entity::player)
            throw std::runtime_error("Pocket state requires a listed player");
        if (lua.getTop(L) == 1) {
            lan::Writer w(lan::Message::world);
            for (unsigned i = 0; i < pocketSlots; ++i) {
                w.u32(at<unsigned>(player, bindings.player.pockets + i * pocketStride));
                w.u32(at<unsigned>(player,
                                   bindings.player.pockets + i * pocketStride + sizeof(unsigned)));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas restore pocket state");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        std::array<std::array<unsigned, 2>, pocketSlots> pockets;
        for (auto& value : pockets) {
            value = {r.u32(), r.u32()};
            if (value[0] > 65535 || value[1] > 2 ||
                (value[1] == 2 && (value[0] < 3 || value[0] > 4)))
                throw std::runtime_error("Invalid ordered pocket state");
        }
        r.finish();
        // Only scalar pocket ID/kind records move. The active-item objects,
        // item acquisition and gameplay remain with inventory reconciliation.
        for (unsigned i = 0; i < pockets.size(); ++i) {
            at<unsigned>(player, bindings.player.pockets + i * pocketStride) = pockets[i][0];
            at<unsigned>(player, bindings.player.pockets + i * pocketStride + sizeof(unsigned)) =
                pockets[i][1];
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int actorCraftingBag(lua_State* L) {
    try {
        auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
        if (!wrapper || lua.rawLength(L, 1) != 8 || wrapper[1] <= bindings.entity.sprite)
            throw std::runtime_error("Invalid crafting bag actor wrapper");
        const auto player = wrapper[1] - bindings.entity.sprite;
        const auto all = context.roster(true);
        if (std::find(all.begin(), all.end(), player) == all.end() ||
            at<unsigned>(player, bindings.entity.type) != compat::ids::entity::player)
            throw std::runtime_error("Crafting bag state requires a listed player");
        if (lua.getTop(L) == 1) {
            lan::Writer w(lan::Message::world);
            for (unsigned i = 0; i < 8; ++i)
                w.u8(at<std::uint8_t>(player, bindings.player.bagMaterials + i));
            w.u32(at<unsigned>(player, bindings.player.bagPreview));
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas restore crafting bag state");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        compat::items::CraftingBagState value;
        for (auto& material : value.materials)
            material = r.u8();
        value.preview = r.u32();
        r.finish();
        if (!compat::items::validCraftingBagState(value))
            throw std::runtime_error("Invalid crafting bag state");
        bool changed = at<unsigned>(player, bindings.player.bagPreview) != value.preview;
        for (unsigned i = 0; i < value.materials.size(); ++i)
            changed |=
                at<std::uint8_t>(player, bindings.player.bagMaterials + i) != value.materials[i];
        if (changed) {
            for (unsigned i = 0; i < value.materials.size(); ++i)
                at<std::uint8_t>(player, bindings.player.bagMaterials + i) = value.materials[i];
            at<unsigned>(player, bindings.player.bagPreview) = value.preview;
            // Vanilla acquisition marks only this actor's owned HUD cache dirty.
            // Repeated snapshots leave its native animation/cache intact.
            using GetHUD = void*(__attribute__((thiscall))*)(void*);
            const auto g = game();
            const auto hud = g ? reinterpret_cast<Address>(
                                     engine<GetHUD>(bindings.getHud)(reinterpret_cast<void*>(g)))
                               : 0;
            for (unsigned i = 0; hud && i < hudSlots; ++i) {
                const auto part = hud + i * bindings.hud.partStride;
                if (at<Address>(part, 0) == player)
                    at<bool>(part, bindings.hud.bagDirty) = true;
            }
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int actorPoop(lua_State* L) {
    auto sprite = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!runtime::replica() || !sprite || lua.rawLength(L, 1) != 8 ||
        sprite[1] <= bindings.entity.sprite) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto player = sprite[1] - bindings.entity.sprite;
    const auto all = context.roster(true);
    if (std::find(all.begin(), all.end(), player) == all.end() ||
        at<unsigned>(player, bindings.entity.type) != compat::ids::entity::player ||
        at<int>(player, bindings.player.type) != compat::ids::player::blueBabyB) {
        lua.pushBoolean(L, false);
        return 1;
    }
    try {
        std::size_t size;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto value = actors::readPoopState(reader);
        at<int>(player, bindings.player.poopMana) = value.mana;
        for (unsigned i = 0; i < value.queue.size(); ++i)
            at<std::uint8_t>(player, bindings.player.poopQueue + i) = value.queue[i];
        lua.pushBoolean(L, true);
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
bool bind(lua_State* L, HMODULE module, Address base, const Callbacks& callbacks) {
    if (!base || !callbacks.roster ||
        !lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::toUserdata, isaac::lua::Symbol::rawLength,
                           isaac::lua::Symbol::newUserdata, isaac::lua::Symbol::getMetatable,
                           isaac::lua::Symbol::setMetatable, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::rawSetI, isaac::lua::Symbol::checkString,
                           isaac::lua::Symbol::pushLString, isaac::lua::Symbol::pushBoolean,
                           isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}))
        return false;
    image = base;
    context = callbacks;
    for (const auto& [name, fn] : {std::pair{"actor_sprites", &actorSprites},
                                   {"actor_pockets", actorPockets},
                                   {"actor_crafting_bag", actorCraftingBag},
                                   {"actor_poop", actorPoop}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace isaac::engine::native_actor_state

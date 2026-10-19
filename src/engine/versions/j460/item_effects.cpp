#include "engine/item_effects.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "compat/items/starting_rewards.h"
#include <MinHook.h>
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include <cstring>
#include <array>

namespace isaac::engine::items {
namespace {
namespace layout = j460::layout;
using Address = std::uintptr_t;
Address image;
isaac::lua::API lua;
using Queue = void(__attribute__((thiscall)) *)(void*, void*, int, unsigned char, int, int);
using Drop = Address(__attribute__((thiscall)) *)(void*, int, void*, bool);
Queue originalQueue;
constexpr unsigned spriteWrapperBytes = 8;
constexpr unsigned playerEntity = 1, maxRoster = 32;
template <class T> T engine(unsigned offset) {
    return reinterpret_cast<T>(image + offset);
}
compat::items::StartingRewards rewards;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
using Add = void(__attribute__((thiscall)) *)(void*, int, int, bool, int, int, int);
Add originalAdd;
void __attribute__((fastcall)) add(void* player, void*, int item, int charge, bool first, int slot,
                                   int data, int unknown) {
    // Only the checked native Blessing grant site is a starting reward. Other
    // character items and AddCollectible calls must never be copied to peers.
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0));
    if (caller == image + j460::entry::edensBlessingGranted)
        rewards.record(item);
    originalAdd(player, item, charge, first, slot, data, unknown);
}
void __attribute__((fastcall)) queue(void* player, void*, void* config, int charge,
                                     unsigned char flags, int data, int pool) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0));
    const auto item = reinterpret_cast<Address>(config);
    const auto actor = reinterpret_cast<Address>(player);
    // Only the successful pedestal acquisition site is intercepted. Lua grants,
    // starting items, crafting and restoration keep the native queue untouched.
    if (caller == image + j460::entry::pickupQueuedCollectible && item &&
        at<int>(item, layout::itemConfig::type) != layout::itemConfig::trinket &&
        runtime::takeCollectiblePickup(at<int>(actor, layout::player::controller) - 1,
                                       at<unsigned>(actor, layout::entity::initSeed),
                                       at<int>(item, layout::itemConfig::id), charge, flags & 1,
                                       data, pool))
        return;
    originalQueue(player, config, charge, flags, data, pool);
}
Address playerArgument(lua_State* L) {
    if (!rooms::virtualized() || runtime::replica() || !rooms::viewReady() ||
        lua.rawLength(L, 1) != spriteWrapperBytes)
        return 0;
    const auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!wrapper || !wrapper[1])
        return 0;
    const auto actor = wrapper[1] - layout::entity::sprite;
    const auto game = at<Address>(image, j460::globals::game);
    if (!game)
        return 0;
    const auto roster = game + layout::game::players;
    const auto first = at<Address>(roster, layout::vector::begin);
    const auto last = at<Address>(roster, layout::vector::end);
    if (last < first || last - first > maxRoster * sizeof(Address))
        return 0;
    bool found = false;
    for (auto entry = first; entry < last; entry += sizeof(Address))
        found |= at<Address>(entry, 0) == actor;
    const auto controller = found ? at<int>(actor, layout::player::controller) : 0;
    return found && controller >= 1 && controller <= 4 &&
                   (rooms::connected() & (1u << (controller - 1))) &&
                   at<unsigned>(actor, layout::entity::type) == playerEntity &&
                   at<bool>(actor, layout::entity::active)
               ? actor
               : 0;
}
Address itemConfig(int id) {
    using Config = Address(__cdecl*)();
    using Item = Address(__attribute__((thiscall))*)(void*, int);
    const auto config = engine<Config>(j460::entry::managerGetItemConfig)();
    return config ? engine<Item>(j460::entry::itemConfigGetCollectible)(
                        reinterpret_cast<void*>(config), id)
                  : 0;
}
int take(lua_State* L) {
    const auto actor = playerArgument(L);
    const int id = static_cast<int>(lua.checkInteger(L, 2));
    if (!actor || !id || !itemConfig(id))
        return 0;
    using Has = bool(__attribute__((thiscall))*)(void*, int, bool);
    if (!engine<Has>(j460::entry::playerHasCollectible)(reinterpret_cast<void*>(actor), id, true))
        return 0;
    // The native method owns inventory removal and active/Schoolbag bookkeeping.
    const auto pickup = engine<Drop>(j460::entry::playerDropCollectible)(
        reinterpret_cast<void*>(actor), id, nullptr, true);
    if (!pickup)
        return 0;
    lua.pushInteger(L, at<int>(pickup, layout::pickup::charge));
    lua.pushInteger(L, at<int>(pickup, layout::pickup::varData));
    lua.pushInteger(L, at<int>(pickup, layout::pickup::pool));
    using Remove = void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Remove>(at<Address>(at<Address>(pickup, 0), layout::entity::removeMethod))(
        reinterpret_cast<void*>(pickup));
    return 3;
}
int give(lua_State* L) {
    const auto actor = playerArgument(L);
    const int id = static_cast<int>(lua.checkInteger(L, 2));
    const int charge = static_cast<int>(lua.checkInteger(L, 3));
    const bool first = lua.toBoolean(L, 4);
    const int data = static_cast<int>(lua.checkInteger(L, 5));
    const int pool = static_cast<int>(lua.checkInteger(L, 6));
    const auto config = itemConfig(id);
    if (!actor || !id || !config) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (at<int>(config, layout::itemConfig::type) == layout::itemConfig::active) {
        const int previous = at<int>(actor, layout::player::primaryActive);
        if (previous)
            engine<Drop>(j460::entry::playerDropCollectible)(reinterpret_cast<void*>(actor),
                                                             previous, nullptr, false);
    }
    originalAdd(reinterpret_cast<void*>(actor), id, charge, first, 0, data, pool);
    lua.pushBoolean(L, true);
    return 1;
}
int name(lua_State* L) {
    const auto config = itemConfig(static_cast<int>(lua.checkInteger(L, 1)));
    if (!config)
        return 0;
    const auto str = config + layout::itemConfig::name;
    const auto size = at<unsigned>(str, layout::string::size);
    if (size > 1024)
        return 0;
    const auto data = at<unsigned>(str, layout::string::capacity) > layout::string::inlineCapacity
                          ? at<Address>(str, 0)
                          : str;
    const char* text = reinterpret_cast<const char*>(data);
    if (size && text[0] == '#') {
        using Lookup =
            const char*(__attribute__((thiscall))*)(void*, const char*, int, const char*, bool*);
        const auto manager = at<Address>(image, j460::globals::manager);
        const auto table = manager + layout::manager::stringTable;
        bool missing = false;
        const auto translated = engine<Lookup>(j460::entry::stringTableLookup)(
            reinterpret_cast<void*>(table), "Items", at<int>(table, 0), text + 1, &missing);
        if (!missing && translated && strnlen(translated, 1025) <= 1024)
            text = translated;
    }
    lua.pushString(L, text);
    return 1;
}
} // namespace
bool install(Address base) {
    image = base;
    const auto target = reinterpret_cast<void*>(image + j460::entry::playerAddCollectible);
    return MH_CreateHook(target, reinterpret_cast<void*>(add),
                         reinterpret_cast<void**>(&originalAdd)) == MH_OK &&
           MH_EnableHook(target) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::playerQueueItem),
                         reinterpret_cast<void*>(queue),
                         reinterpret_cast<void**>(&originalQueue)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::playerQueueItem)) == MH_OK;
}
bool bind(lua_State* L, HMODULE module) {
    using S = isaac::lua::Symbol;
    if (!lua.load(module,
                  {S::toUserdata, S::rawLength, S::checkInteger, S::toBoolean, S::pushInteger,
                   S::pushBoolean, S::pushString, S::pushClosure, S::setField}))
        return false;
    for (const auto& [key, fn] : std::array<std::pair<const char*, isaac::lua::Function>, 3>{
             {{"items_take_collectible", take},
              {"items_give_collectible", give},
              {"items_collectible_name", name}}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, key);
    }
    return true;
}
void startingRewards(const std::function<void()>& start, bool shared) {
    rewards = {};
    if (shared)
        rewards.begin();
    start();
    rewards.finish();
}
void grantStartingRewards(void* player, unsigned slot) {
    for (const int item : rewards.take(slot))
        originalAdd(player, item, -1, true, 0, 0, 0);
}
void leaveRoom(void* player) {
    const auto address = reinterpret_cast<Address>(player);
    const auto beam = at<Address>(address, layout::player::megaBlastLaser);
    if (!beam)
        return;
    // Remove the departure room's laser through its engine owner, then detach
    // the registered EntityPtr. Player::Update creates the next room's laser
    // using the unchanged native remaining duration; item use is not replayed.
    using Remove = void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Remove>(at<Address>(at<Address>(beam, 0), layout::entity::removeMethod))(
        reinterpret_cast<void*>(beam));
    using Assign = void(__attribute__((fastcall))*)(void*, void*);
    reinterpret_cast<Assign>(image + j460::entry::entityPtrAssign)(
        reinterpret_cast<void*>(address + layout::player::megaBlastLaser), nullptr);
}
} // namespace isaac::engine::items

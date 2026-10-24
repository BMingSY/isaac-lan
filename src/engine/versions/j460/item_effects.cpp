#include "engine/item_effects.h"
#include "engine/rooms.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "compat/items/starting_rewards.h"
#include <MinHook.h>
#include "engine/lua_api.h"
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
using ReviveCollectible = void(__attribute__((thiscall)) *)(void*, unsigned, bool);
// J460 consumes two stack words (RET 8). The second is an unused caller
// scratch word, absent from older public prototypes; preserve it verbatim.
using ReviveTrinket = void(__attribute__((thiscall)) *)(void*, unsigned, unsigned);
ReviveCollectible originalReviveCollectible;
ReviveTrinket originalReviveTrinket;
void inRevivalRoom(void* player, const std::function<void()>& revive) {
    const auto controller =
        at<unsigned>(reinterpret_cast<Address>(player), layout::player::controller);
    // PlayerManager resolves pending deaths outside Room::Update. Its current
    // viewport is not necessarily the revived actor's room. Existing scopes
    // and solo play already own the correct native context.
    if (!rooms::withPlayer(controller - 1, revive))
        revive();
}
void __attribute__((fastcall)) reviveCollectible(void* player, void*, unsigned item, bool owned) {
    inRevivalRoom(player, [&] { originalReviveCollectible(player, item, owned); });
}
void __attribute__((fastcall)) reviveTrinket(void* player, void*, unsigned item, unsigned scratch) {
    inRevivalRoom(player, [&] { originalReviveTrinket(player, item, scratch); });
}
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
int activeCharge(lua_State* L) {
    const auto actor = playerArgument(L);
    const int slot = static_cast<int>(lua.checkInteger(L, 2));
    if (!actor || slot < 0 || slot >= 4)
        return 0;
    using Query = int(__attribute__((thiscall))*)(void*, int);
    auto player = reinterpret_cast<void*>(actor);
    lua.pushInteger(L, engine<Query>(j460::entry::playerActiveChargeType)(player, slot));
    lua.pushInteger(L, engine<Query>(j460::entry::playerActiveMaxCharge)(player, slot));
    return 2;
}
int addActiveCharge(lua_State* L) {
    const auto actor = playerArgument(L);
    const int slot = static_cast<int>(lua.checkInteger(L, 2));
    const int amount = static_cast<int>(lua.checkInteger(L, 3));
    if (!actor || slot < 0 || slot >= 4 || amount < 0 || amount > 1024)
        return 0;
    // J460 thiscall, RET 20. Native owns capacity, charge type, battery overflow
    // and the charge-complete presentation. No discharge or forced overcharge.
    using AddCharge = int(__attribute__((thiscall))*)(void*, int, int, bool, bool, bool);
    lua.pushInteger(L, engine<AddCharge>(j460::entry::playerAddActiveCharge)(
                           reinterpret_cast<void*>(actor), amount, slot, false, false, false));
    return 1;
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
    auto hook = [&](unsigned entry, auto replacement, auto& original) {
        const auto target = reinterpret_cast<void*>(image + entry);
        return MH_CreateHook(target, reinterpret_cast<void*>(replacement),
                             reinterpret_cast<void**>(&original)) == MH_OK &&
               MH_EnableHook(target) == MH_OK;
    };
    return hook(j460::entry::playerAddCollectible, add, originalAdd) &&
           hook(j460::entry::playerQueueItem, queue, originalQueue) &&
           hook(j460::entry::playerReviveCollectible, reviveCollectible,
                originalReviveCollectible) &&
           hook(j460::entry::playerReviveTrinket, reviveTrinket, originalReviveTrinket);
}
bool bind(lua_State* L, HMODULE module) {
    using S = isaac::lua::Symbol;
    if (!lua.load(module,
                  {S::toUserdata, S::rawLength, S::checkInteger, S::toBoolean, S::pushInteger,
                   S::pushBoolean, S::pushString, S::pushClosure, S::setField}))
        return false;
    for (const auto& [key, fn] : std::array<std::pair<const char*, isaac::lua::Function>, 5>{
             {{"items_take_collectible", take},
              {"items_give_collectible", give},
              {"items_collectible_name", name},
              {"items_active_charge", activeCharge},
              {"items_add_active_charge", addActiveCharge}}}) {
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
bool initializeBlueRoom(void* game, int source, int destination, int direction) {
    using Initialize = bool(__attribute__((thiscall))*)(void*, int, int, int);
    return reinterpret_cast<Initialize>(image + j460::entry::levelTryInitializeBlueRoom)(
        game, source, destination, direction);
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

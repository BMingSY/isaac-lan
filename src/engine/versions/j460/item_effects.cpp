#include "engine/item_effects.h"
#include "engine/rooms.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "compat/items/starting_rewards.h"
#include <MinHook.h>

namespace isaac::engine::items {
namespace {
namespace layout = j460::layout;
using Address = std::uintptr_t;
Address image;
compat::items::StartingRewards rewards;
template <class T> T& at(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
using Add = void(__attribute__((thiscall)) *)(void*, int, int, bool, int, int, int);
Add originalAdd;
using ReviveCollectible = void(__attribute__((thiscall)) *)(void*, unsigned, bool);
using ReviveTrinket = void(__attribute__((thiscall)) *)(void*, unsigned);
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
void __attribute__((fastcall)) reviveTrinket(void* player, void*, unsigned item) {
    inRevivalRoom(player, [&] { originalReviveTrinket(player, item); });
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
           hook(j460::entry::playerReviveCollectible, reviveCollectible,
                originalReviveCollectible) &&
           hook(j460::entry::playerReviveTrinket, reviveTrinket, originalReviveTrinket);
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

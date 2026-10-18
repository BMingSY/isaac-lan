#include "engine/item_effects.h"
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
    const auto target = reinterpret_cast<void*>(image + j460::entry::playerAddCollectible);
    return MH_CreateHook(target, reinterpret_cast<void*>(add),
                         reinterpret_cast<void**>(&originalAdd)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
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

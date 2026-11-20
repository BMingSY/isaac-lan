#include <windows.h>
#include "engine/versions/common/item_bindings.h"
#include "engine/versions/j510/active_items.h"
#include "engine/versions/j510/inventory_order.h"
#include "engine/versions/j510/smelted_trinkets.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"
#include "engine/versions/j510/cursed_mist.h"
#include "engine/versions/common/death_certificate_return.h"

namespace isaac::engine::native_items {
namespace {
bool installCompatibility(std::uintptr_t image) {
    return j510::cursed_mist::install(image) && native_certificate_return::install(image);
}
int chargeType(std::uintptr_t image, void* player, int slot) {
    using Query = int(__attribute__((thiscall))*)(void*, int);
    return reinterpret_cast<Query>(image + j510::entry::playerActiveChargeType)(player, slot);
}
} // namespace
const Bindings bindings{
    .entry = {j510::entry::playerAddCollectible, j510::entry::playerQueueItem,
              j510::entry::edensBlessingGranted, j510::entry::pickupQueuedCollectible,
              j510::entry::playerReviveCollectible, j510::entry::playerReviveTrinket,
              j510::entry::managerGetItemConfig, j510::entry::itemConfigGetCollectible,
              j510::entry::playerHasCollectible, j510::entry::playerDropCollectible,
              j510::entry::playerActiveMaxCharge, j510::entry::playerAddActiveCharge,
              j510::entry::stringTableLookup, j510::entry::levelTryInitializeBlueRoom,
              j510::entry::entityPtrAssign},
    .globals = {j510::globals::game, j510::globals::manager},
    .layout =
        {
            .player = {j510::layout::player::controller, j510::layout::player::primaryActive,
                       j510::layout::player::megaBlastLaser},
            .entity = {j510::layout::entity::sprite, j510::layout::entity::initSeed,
                       j510::layout::entity::type, j510::layout::entity::active,
                       j510::layout::entity::removeMethod},
            .game = {j510::layout::game::players},
            .manager = {j510::layout::manager::stringTable},
            .string = {j510::layout::string::size, j510::layout::string::capacity,
                       j510::layout::string::inlineCapacity},
            .vector = {j510::layout::vector::begin, j510::layout::vector::end},
            .itemConfig = {j510::layout::itemConfig::type, j510::layout::itemConfig::id,
                           j510::layout::itemConfig::name, j510::layout::itemConfig::active,
                           j510::layout::itemConfig::trinket},
            .pickup = {j510::layout::pickup::charge, j510::layout::pickup::varData,
                       j510::layout::pickup::pool},
        },
    .chargeType = chargeType,
    .activeItems = j510::active_items::fields,
    .inventoryOrder = j510::inventory_order::fields,
    .smeltedTrinkets = j510::smelted_trinkets::fields,
    .installCompatibility = installCompatibility};
} // namespace isaac::engine::native_items

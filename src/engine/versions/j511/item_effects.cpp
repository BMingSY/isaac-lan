#include <windows.h>
#include "engine/versions/common/item_bindings.h"
#include "engine/versions/j511/active_items.h"
#include "engine/versions/j511/inventory_order.h"
#include "engine/versions/j511/smelted_trinkets.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
#include "engine/versions/j511/cursed_mist.h"
#include "engine/versions/common/death_certificate_return.h"

namespace isaac::engine::native_items {
namespace {
bool installCompatibility(std::uintptr_t image) {
    return j511::cursed_mist::install(image) && native_certificate_return::install(image);
}
int chargeType(std::uintptr_t image, void* player, int slot) {
    using Query = int(__attribute__((thiscall))*)(void*, int);
    return reinterpret_cast<Query>(image + j511::entry::playerActiveChargeType)(player, slot);
}
} // namespace
const Bindings bindings{
    .entry = {j511::entry::playerAddCollectible, j511::entry::playerQueueItem,
              j511::entry::edensBlessingGranted, j511::entry::pickupQueuedCollectible,
              j511::entry::playerReviveCollectible, j511::entry::playerReviveTrinket,
              j511::entry::managerGetItemConfig, j511::entry::itemConfigGetCollectible,
              j511::entry::playerHasCollectible, j511::entry::playerDropCollectible,
              j511::entry::playerActiveMaxCharge, j511::entry::playerAddActiveCharge,
              j511::entry::stringTableLookup, j511::entry::levelTryInitializeBlueRoom,
              j511::entry::entityPtrAssign},
    .globals = {j511::globals::game, j511::globals::manager},
    .layout =
        {
            .player = {j511::layout::player::controller, j511::layout::player::primaryActive,
                       j511::layout::player::megaBlastLaser},
            .entity = {j511::layout::entity::sprite, j511::layout::entity::initSeed,
                       j511::layout::entity::type, j511::layout::entity::active,
                       j511::layout::entity::removeMethod},
            .game = {j511::layout::game::players},
            .manager = {j511::layout::manager::stringTable},
            .string = {j511::layout::string::size, j511::layout::string::capacity,
                       j511::layout::string::inlineCapacity},
            .vector = {j511::layout::vector::begin, j511::layout::vector::end},
            .itemConfig = {j511::layout::itemConfig::type, j511::layout::itemConfig::id,
                           j511::layout::itemConfig::name, j511::layout::itemConfig::active,
                           j511::layout::itemConfig::trinket},
            .pickup = {j511::layout::pickup::charge, j511::layout::pickup::varData,
                       j511::layout::pickup::pool},
        },
    .chargeType = chargeType,
    .activeItems = j511::active_items::fields,
    .inventoryOrder = j511::inventory_order::fields,
    .smeltedTrinkets = j511::smelted_trinkets::fields,
    .installCompatibility = installCompatibility};
} // namespace isaac::engine::native_items

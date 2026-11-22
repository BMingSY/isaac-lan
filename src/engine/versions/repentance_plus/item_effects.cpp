#include <windows.h>
#include "engine/versions/common/item_bindings.h"
#include "engine/versions/repentance_plus/active_items.h"
#include "engine/versions/repentance_plus/inventory_order.h"
#include "engine/versions/repentance_plus/smelted_trinkets.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/cursed_mist.h"
#include "engine/versions/common/death_certificate_return.h"

namespace isaac::engine::native_items {
namespace {
bool installCompatibility(std::uintptr_t image) {
    return repentance_plus::cursed_mist::install(image) &&
           native_certificate_return::install(image);
}
int chargeType(std::uintptr_t image, void* player, int slot) {
    using Query = int(__attribute__((thiscall))*)(void*, int);
    return reinterpret_cast<Query>(image + repentance_plus::entry::playerActiveChargeType)(player,
                                                                                           slot);
}
} // namespace
const Bindings bindings{
    .entry = {repentance_plus::entry::playerAddCollectible, repentance_plus::entry::playerQueueItem,
              repentance_plus::entry::edensBlessingGranted,
              repentance_plus::entry::pickupQueuedCollectible,
              repentance_plus::entry::playerReviveCollectible,
              repentance_plus::entry::playerReviveTrinket,
              repentance_plus::entry::managerGetItemConfig,
              repentance_plus::entry::itemConfigGetCollectible,
              repentance_plus::entry::playerHasCollectible,
              repentance_plus::entry::playerDropCollectible,
              repentance_plus::entry::playerActiveMaxCharge,
              repentance_plus::entry::playerAddActiveCharge,
              repentance_plus::entry::stringTableLookup,
              repentance_plus::entry::levelTryInitializeBlueRoom,
              repentance_plus::entry::entityPtrAssign},
    .globals = {repentance_plus::globals::game, repentance_plus::globals::manager},
    .layout =
        {
            .player = {repentance_plus::layout::player::controller,
                       repentance_plus::layout::player::primaryActive,
                       repentance_plus::layout::player::megaBlastLaser},
            .entity = {repentance_plus::layout::entity::sprite,
                       repentance_plus::layout::entity::initSeed,
                       repentance_plus::layout::entity::type,
                       repentance_plus::layout::entity::active,
                       repentance_plus::layout::entity::removeMethod},
            .game = {repentance_plus::layout::game::players},
            .manager = {repentance_plus::layout::manager::stringTable},
            .string = {repentance_plus::layout::string::size,
                       repentance_plus::layout::string::capacity,
                       repentance_plus::layout::string::inlineCapacity},
            .vector = {repentance_plus::layout::vector::begin,
                       repentance_plus::layout::vector::end},
            .itemConfig = {repentance_plus::layout::itemConfig::type,
                           repentance_plus::layout::itemConfig::id,
                           repentance_plus::layout::itemConfig::name,
                           repentance_plus::layout::itemConfig::active,
                           repentance_plus::layout::itemConfig::trinket},
            .pickup = {repentance_plus::layout::pickup::charge,
                       repentance_plus::layout::pickup::varData,
                       repentance_plus::layout::pickup::pool},
        },
    .chargeType = chargeType,
    .activeItems = repentance_plus::active_items::fields,
    .inventoryOrder = repentance_plus::inventory_order::fields,
    .smeltedTrinkets = repentance_plus::smelted_trinkets::fields,
    .installCompatibility = installCompatibility};
} // namespace isaac::engine::native_items

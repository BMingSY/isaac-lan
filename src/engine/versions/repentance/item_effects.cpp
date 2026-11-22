#include <windows.h>
#include "engine/versions/common/item_bindings.h"
#include "engine/versions/common/death_certificate_return.h"
#include "engine/versions/repentance/active_items.h"
#include "engine/versions/repentance/inventory_order.h"
#include "engine/versions/repentance/smelted_trinkets.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_items {
namespace {
int chargeType(std::uintptr_t image, void* player, int slot) {
    // Original AddActiveCharge uses the active item's config ChargeType. There
    // is no Plus-specific charge-type method or extra source-pool argument.
    const auto actor = reinterpret_cast<std::uintptr_t>(player);
    const auto id =
        *reinterpret_cast<const int*>(actor + repentance::layout::player::primaryActive +
                                      slot * repentance::layout::player::activeStride);
    if (!id)
        return repentance::layout::itemConfig::specialCharge;
    using Config = void*(__cdecl*)();
    using Item = std::uintptr_t(__attribute__((thiscall))*)(void*, int);
    const auto config = reinterpret_cast<Config>(image + repentance::entry::managerGetItemConfig)();
    const auto item = config ? reinterpret_cast<Item>(
                                   image + repentance::entry::itemConfigGetCollectible)(config, id)
                             : 0;
    return item ? *reinterpret_cast<const int*>(item + repentance::layout::itemConfig::chargeType)
                : repentance::layout::itemConfig::specialCharge;
}
} // namespace
const Bindings bindings{
    .entry = {repentance::entry::playerAddCollectible, repentance::entry::playerQueueItem,
              repentance::entry::edensBlessingGranted, repentance::entry::pickupQueuedCollectible,
              repentance::entry::playerReviveCollectible, repentance::entry::playerReviveTrinket,
              repentance::entry::managerGetItemConfig, repentance::entry::itemConfigGetCollectible,
              repentance::entry::playerHasCollectible, repentance::entry::playerDropCollectible,
              repentance::entry::playerActiveMaxCharge, repentance::entry::playerAddActiveCharge,
              repentance::entry::stringTableLookup, repentance::entry::levelTryInitializeBlueRoom,
              repentance::entry::entityPtrAssign},
    .globals = {repentance::globals::game, repentance::globals::manager},
    .layout =
        {
            .player = {repentance::layout::player::controller,
                       repentance::layout::player::primaryActive,
                       repentance::layout::player::megaBlastLaser},
            .entity = {repentance::layout::entity::sprite, repentance::layout::entity::initSeed,
                       repentance::layout::entity::type, repentance::layout::entity::active,
                       repentance::layout::entity::removeMethod},
            .game = {repentance::layout::game::players},
            .manager = {repentance::layout::manager::stringTable},
            .string = {repentance::layout::string::size, repentance::layout::string::capacity,
                       repentance::layout::string::inlineCapacity},
            .vector = {repentance::layout::vector::begin, repentance::layout::vector::end},
            .itemConfig = {repentance::layout::itemConfig::type, repentance::layout::itemConfig::id,
                           repentance::layout::itemConfig::name,
                           repentance::layout::itemConfig::active,
                           repentance::layout::itemConfig::trinket},
            .pickup = {repentance::layout::pickup::charge, repentance::layout::pickup::varData,
                       std::nullopt},
        },
    .chargeType = chargeType,
    .activeItems = repentance::active_items::fields,
    .inventoryOrder = repentance::inventory_order::fields,
    .smeltedTrinkets = repentance::smelted_trinkets::fields,
    .installCompatibility = native_certificate_return::install};
} // namespace isaac::engine::native_items

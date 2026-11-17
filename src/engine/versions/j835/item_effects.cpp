#include <windows.h>
#include "engine/versions/common/item_bindings.h"
#include "engine/versions/common/death_certificate_return.h"
#include "engine/versions/j835/active_items.h"
#include "engine/versions/j835/inventory_order.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_items {
namespace {
int chargeType(std::uintptr_t image, void* player, int slot) {
    // Original AddActiveCharge uses the active item's config ChargeType. There
    // is no Plus-specific charge-type method or extra source-pool argument.
    const auto actor = reinterpret_cast<std::uintptr_t>(player);
    const auto id = *reinterpret_cast<const int*>(actor + j835::layout::player::primaryActive +
                                                  slot * j835::layout::player::activeStride);
    if (!id)
        return j835::layout::itemConfig::specialCharge;
    using Config = void*(__cdecl*)();
    using Item = std::uintptr_t(__attribute__((thiscall))*)(void*, int);
    const auto config = reinterpret_cast<Config>(image + j835::entry::managerGetItemConfig)();
    const auto item =
        config ? reinterpret_cast<Item>(image + j835::entry::itemConfigGetCollectible)(config, id)
               : 0;
    return item ? *reinterpret_cast<const int*>(item + j835::layout::itemConfig::chargeType)
                : j835::layout::itemConfig::specialCharge;
}
} // namespace
const Bindings bindings{
    .entry = {j835::entry::playerAddCollectible, j835::entry::playerQueueItem,
              j835::entry::edensBlessingGranted, j835::entry::pickupQueuedCollectible,
              j835::entry::playerReviveCollectible, j835::entry::playerReviveTrinket,
              j835::entry::managerGetItemConfig, j835::entry::itemConfigGetCollectible,
              j835::entry::playerHasCollectible, j835::entry::playerDropCollectible,
              j835::entry::playerActiveMaxCharge, j835::entry::playerAddActiveCharge,
              j835::entry::stringTableLookup, j835::entry::levelTryInitializeBlueRoom,
              j835::entry::entityPtrAssign},
    .globals = {j835::globals::game, j835::globals::manager},
    .layout =
        {
            .player = {j835::layout::player::controller, j835::layout::player::primaryActive,
                       j835::layout::player::megaBlastLaser},
            .entity = {j835::layout::entity::sprite, j835::layout::entity::initSeed,
                       j835::layout::entity::type, j835::layout::entity::active,
                       j835::layout::entity::removeMethod},
            .game = {j835::layout::game::players},
            .manager = {j835::layout::manager::stringTable},
            .string = {j835::layout::string::size, j835::layout::string::capacity,
                       j835::layout::string::inlineCapacity},
            .vector = {j835::layout::vector::begin, j835::layout::vector::end},
            .itemConfig = {j835::layout::itemConfig::type, j835::layout::itemConfig::id,
                           j835::layout::itemConfig::name, j835::layout::itemConfig::active,
                           j835::layout::itemConfig::trinket},
            .pickup = {j835::layout::pickup::charge, j835::layout::pickup::varData, std::nullopt},
        },
    .chargeType = chargeType,
    .activeItems = j835::active_items::fields,
    .inventoryOrder = j835::inventory_order::fields,
    .installCompatibility = native_certificate_return::install};
} // namespace isaac::engine::native_items

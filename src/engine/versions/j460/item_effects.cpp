#include <windows.h>
#include "engine/versions/common/item_bindings.h"
#include "engine/versions/j460/active_items.h"
#include "engine/versions/j460/inventory_order.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/cursed_mist.h"
#include "engine/versions/j460/death_certificate_return.h"

namespace isaac::engine::native_items {
namespace {
bool installCompatibility(std::uintptr_t image) {
    return j460::cursed_mist::install(image) && j460::installDeathCertificateReturn(image);
}
int chargeType(std::uintptr_t image, void* player, int slot) {
    using Query = int(__attribute__((thiscall))*)(void*, int);
    return reinterpret_cast<Query>(image + j460::entry::playerActiveChargeType)(player, slot);
}
} // namespace
const Bindings bindings{
    .entry = {j460::entry::playerAddCollectible, j460::entry::playerQueueItem,
              j460::entry::edensBlessingGranted, j460::entry::pickupQueuedCollectible,
              j460::entry::playerReviveCollectible, j460::entry::playerReviveTrinket,
              j460::entry::managerGetItemConfig, j460::entry::itemConfigGetCollectible,
              j460::entry::playerHasCollectible, j460::entry::playerDropCollectible,
              j460::entry::playerActiveMaxCharge, j460::entry::playerAddActiveCharge,
              j460::entry::stringTableLookup, j460::entry::levelTryInitializeBlueRoom,
              j460::entry::entityPtrAssign},
    .globals = {j460::globals::game, j460::globals::manager},
    .layout =
        {
            .player = {j460::layout::player::controller, j460::layout::player::primaryActive,
                       j460::layout::player::megaBlastLaser},
            .entity = {j460::layout::entity::sprite, j460::layout::entity::initSeed,
                       j460::layout::entity::type, j460::layout::entity::active,
                       j460::layout::entity::removeMethod},
            .game = {j460::layout::game::players},
            .manager = {j460::layout::manager::stringTable},
            .string = {j460::layout::string::size, j460::layout::string::capacity,
                       j460::layout::string::inlineCapacity},
            .vector = {j460::layout::vector::begin, j460::layout::vector::end},
            .itemConfig = {j460::layout::itemConfig::type, j460::layout::itemConfig::id,
                           j460::layout::itemConfig::name, j460::layout::itemConfig::active,
                           j460::layout::itemConfig::trinket},
            .pickup = {j460::layout::pickup::charge, j460::layout::pickup::varData,
                       j460::layout::pickup::pool},
        },
    .chargeType = chargeType,
    .activeItems = j460::active_items::fields,
    .inventoryOrder = j460::inventory_order::fields,
    .installCompatibility = installCompatibility};
} // namespace isaac::engine::native_items

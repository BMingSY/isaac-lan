#pragma once
#include <cstdint>
#include <optional>
#include "engine/versions/common/active_items.h"
#include "engine/versions/common/inventory_order.h"
#include "engine/versions/common/smelted_trinkets.h"

namespace isaac::engine::native_items {
// Backend-private layouts and calls. Optional pickup pool identifies the native
// AddCollectible/QueueItem ABI: original Repentance has no pool field/argument.
struct Bindings {
    struct Entries {
        std::uint32_t playerAddCollectible, playerQueueItem, edensBlessingGranted;
        std::uint32_t pickupQueuedCollectible, playerReviveCollectible, playerReviveTrinket;
        std::uint32_t managerGetItemConfig, itemConfigGetCollectible, playerHasCollectible;
        std::uint32_t playerDropCollectible, playerActiveMaxCharge, playerAddActiveCharge;
        std::uint32_t stringTableLookup, levelTryInitializeBlueRoom, entityPtrAssign;
    } entry;
    struct Globals {
        std::uint32_t game, manager;
    } globals;
    struct Layout {
        struct Player {
            unsigned controller, primaryActive, megaBlastLaser;
        } player;
        struct Entity {
            unsigned sprite, initSeed, type, active, removeMethod;
        } entity;
        struct Game {
            unsigned players;
        } game;
        struct Manager {
            unsigned stringTable;
        } manager;
        struct String {
            unsigned size, capacity, inlineCapacity;
        } string;
        struct Vector {
            unsigned begin, end;
        } vector;
        struct ItemConfig {
            unsigned type, id, name;
            int active, trinket;
        } itemConfig;
        struct Pickup {
            unsigned charge, varData;
            std::optional<unsigned> pool;
        } pickup;
    } layout;
    int (*chargeType)(std::uintptr_t, void*, int);
    native_active_items::Layout activeItems;
    native_inventory_order::Layout inventoryOrder;
    native_smelted_trinkets::Layout smeltedTrinkets;
    bool (*installCompatibility)(std::uintptr_t) = nullptr;
};
extern const Bindings bindings;
inline constexpr int unavailablePool = 0;
} // namespace isaac::engine::native_items

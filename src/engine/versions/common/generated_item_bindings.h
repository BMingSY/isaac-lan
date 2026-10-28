#pragma once
#include <cstdint>

namespace isaac::engine::native_generated_items {
struct Bindings {
    struct Entries {
        std::uint32_t create, restoreCall;
    } entry;
    std::uint32_t game;
    struct Layout {
        struct Player {
            unsigned generatedInventoryHead, generatedInventorySize;
        } player;
        struct Game {
            unsigned players, generatedItems;
        } game;
        struct Entity {
            unsigned sprite, type;
        } entity;
        struct Vector {
            unsigned begin, end;
        } vector;
        struct Definition {
            unsigned config, seed, configId;
        } generatedItem;
        struct InventoryNode {
            unsigned left, parent, right, nil, id, count;
        } inventoryNode;
    } layout;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_generated_items

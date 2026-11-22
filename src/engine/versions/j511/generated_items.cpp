#include "engine/versions/common/generated_item_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_generated_items {
const Bindings bindings{
    .entry = {j511::entry::generatedItemCreate, j511::entry::generatedItemRestoreCall,
              j511::entry::generatedItemTrigger},
    .game = j511::globals::game,
    .layout = {
        .player = {j511::layout::player::generatedInventoryHead,
                   j511::layout::player::generatedInventorySize},
        .game = {j511::layout::game::players, j511::layout::game::generatedItems},
        .entity = {j511::layout::entity::sprite, j511::layout::entity::type},
        .vector = {j511::layout::vector::begin, j511::layout::vector::end},
        .generatedItem = {j511::layout::generatedItem::config, j511::layout::generatedItem::seed,
                          j511::layout::generatedItem::configId},
        .inventoryNode = {j511::layout::inventoryNode::left, j511::layout::inventoryNode::parent,
                          j511::layout::inventoryNode::right, j511::layout::inventoryNode::nil,
                          j511::layout::inventoryNode::id, j511::layout::inventoryNode::count}}};
} // namespace isaac::engine::native_generated_items

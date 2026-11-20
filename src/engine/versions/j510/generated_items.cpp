#include "engine/versions/common/generated_item_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_generated_items {
const Bindings bindings{
    .entry = {j510::entry::generatedItemCreate, j510::entry::generatedItemRestoreCall,
              j510::entry::generatedItemTrigger},
    .game = j510::globals::game,
    .layout = {
        .player = {j510::layout::player::generatedInventoryHead,
                   j510::layout::player::generatedInventorySize},
        .game = {j510::layout::game::players, j510::layout::game::generatedItems},
        .entity = {j510::layout::entity::sprite, j510::layout::entity::type},
        .vector = {j510::layout::vector::begin, j510::layout::vector::end},
        .generatedItem = {j510::layout::generatedItem::config, j510::layout::generatedItem::seed,
                          j510::layout::generatedItem::configId},
        .inventoryNode = {j510::layout::inventoryNode::left, j510::layout::inventoryNode::parent,
                          j510::layout::inventoryNode::right, j510::layout::inventoryNode::nil,
                          j510::layout::inventoryNode::id, j510::layout::inventoryNode::count}}};
} // namespace isaac::engine::native_generated_items

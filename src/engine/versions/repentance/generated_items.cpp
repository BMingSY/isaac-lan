#include "engine/versions/common/generated_item_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_generated_items {
const Bindings bindings{
    .entry = {repentance::entry::generatedItemCreate, repentance::entry::generatedItemRestoreCall,
              repentance::entry::generatedItemTrigger},
    .game = repentance::globals::game,
    .layout = {
        .player = {repentance::layout::player::generatedInventoryHead,
                   repentance::layout::player::generatedInventorySize},
        .game = {repentance::layout::game::players, repentance::layout::game::generatedItems},
        .entity = {repentance::layout::entity::sprite, repentance::layout::entity::type},
        .vector = {repentance::layout::vector::begin, repentance::layout::vector::end},
        .generatedItem = {repentance::layout::generatedItem::config,
                          repentance::layout::generatedItem::seed,
                          repentance::layout::generatedItem::configId},
        .inventoryNode = {
            repentance::layout::inventoryNode::left, repentance::layout::inventoryNode::parent,
            repentance::layout::inventoryNode::right, repentance::layout::inventoryNode::nil,
            repentance::layout::inventoryNode::id, repentance::layout::inventoryNode::count}}};
} // namespace isaac::engine::native_generated_items

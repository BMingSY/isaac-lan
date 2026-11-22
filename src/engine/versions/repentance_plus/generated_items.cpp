#include "engine/versions/common/generated_item_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_generated_items {
const Bindings bindings{
    .entry = {repentance_plus::entry::generatedItemCreate,
              repentance_plus::entry::generatedItemRestoreCall,
              repentance_plus::entry::generatedItemTrigger},
    .game = repentance_plus::globals::game,
    .layout = {
        .player = {repentance_plus::layout::player::generatedInventoryHead,
                   repentance_plus::layout::player::generatedInventorySize},
        .game = {repentance_plus::layout::game::players,
                 repentance_plus::layout::game::generatedItems},
        .entity = {repentance_plus::layout::entity::sprite, repentance_plus::layout::entity::type},
        .vector = {repentance_plus::layout::vector::begin, repentance_plus::layout::vector::end},
        .generatedItem = {repentance_plus::layout::generatedItem::config,
                          repentance_plus::layout::generatedItem::seed,
                          repentance_plus::layout::generatedItem::configId},
        .inventoryNode = {repentance_plus::layout::inventoryNode::left,
                          repentance_plus::layout::inventoryNode::parent,
                          repentance_plus::layout::inventoryNode::right,
                          repentance_plus::layout::inventoryNode::nil,
                          repentance_plus::layout::inventoryNode::id,
                          repentance_plus::layout::inventoryNode::count}}};
} // namespace isaac::engine::native_generated_items

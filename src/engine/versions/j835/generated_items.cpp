#include "engine/versions/common/generated_item_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_generated_items {
const Bindings bindings{
    .entry = {j835::entry::generatedItemCreate, j835::entry::generatedItemRestoreCall},
    .game = j835::globals::game,
    .layout = {
        .player = {j835::layout::player::generatedInventoryHead,
                   j835::layout::player::generatedInventorySize},
        .game = {j835::layout::game::players, j835::layout::game::generatedItems},
        .entity = {j835::layout::entity::sprite, j835::layout::entity::type},
        .vector = {j835::layout::vector::begin, j835::layout::vector::end},
        .generatedItem = {j835::layout::generatedItem::config, j835::layout::generatedItem::seed,
                          j835::layout::generatedItem::configId},
        .inventoryNode = {j835::layout::inventoryNode::left, j835::layout::inventoryNode::parent,
                          j835::layout::inventoryNode::right, j835::layout::inventoryNode::nil,
                          j835::layout::inventoryNode::id, j835::layout::inventoryNode::count}}};
} // namespace isaac::engine::native_generated_items

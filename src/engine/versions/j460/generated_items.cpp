#include "engine/versions/common/generated_item_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_generated_items {
const Bindings bindings{
    .entry = {j460::entry::generatedItemCreate, j460::entry::generatedItemRestoreCall},
    .game = j460::globals::game,
    .layout = {
        .player = {j460::layout::player::generatedInventoryHead,
                   j460::layout::player::generatedInventorySize},
        .game = {j460::layout::game::players, j460::layout::game::generatedItems},
        .entity = {j460::layout::entity::sprite, j460::layout::entity::type},
        .vector = {j460::layout::vector::begin, j460::layout::vector::end},
        .generatedItem = {j460::layout::generatedItem::config, j460::layout::generatedItem::seed,
                          j460::layout::generatedItem::configId},
        .inventoryNode = {j460::layout::inventoryNode::left, j460::layout::inventoryNode::parent,
                          j460::layout::inventoryNode::right, j460::layout::inventoryNode::nil,
                          j460::layout::inventoryNode::id, j460::layout::inventoryNode::count}}};
} // namespace isaac::engine::native_generated_items

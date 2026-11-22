#pragma once
#include "engine/versions/common/inventory_order.h"
#include "engine/versions/repentance/layout.h"
namespace isaac::engine::repentance::inventory_order {
using native_inventory_order::State;
using Address = std::uintptr_t;
inline constexpr native_inventory_order::Layout fields{
    layout::player::inventoryOrder, layout::player::history,   layout::historyItem::size,
    layout::historyItem::trinket,   layout::historyItem::id,   layout::game::playerHuds,
    layout::playerHud::size,        layout::playerHud::player, layout::playerHud::refreshFlags};
inline State capture(Address player) {
    return native_inventory_order::capture(fields, player);
}
inline void restore(Address player, Address game, const State& state) {
    native_inventory_order::restore(fields, player, game, state);
}
inline State indices(Address player) {
    return native_inventory_order::indices(fields, player);
}
} // namespace isaac::engine::repentance::inventory_order

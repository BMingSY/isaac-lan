#pragma once
#include "engine/versions/common/active_items.h"
#include "engine/versions/j511/layout.h"
namespace isaac::engine::j511::active_items {
using native_active_items::State;
using Address = std::uintptr_t;
inline constexpr native_active_items::Layout fields{
    layout::player::primaryActive,  layout::activeItem::stride,     layout::activeItem::data,
    layout::game::playerHuds,       layout::playerHud::size,        layout::playerHud::player,
    layout::playerHud::activeItems, layout::playerHud::activeStride};
inline State capture(Address player) {
    return native_active_items::capture(fields, player);
}
inline void restore(Address player, Address game, const State& state) {
    native_active_items::restore(fields, player, game, state);
}
using native_active_items::Item;
} // namespace isaac::engine::j511::active_items

#pragma once
#include "compat/items/active_data.h"
#include "engine/versions/j460/layout.h"
#include <array>
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::j460::active_items {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
struct Item {
    std::int32_t id = 0, data = 0;
    bool operator==(const Item&) const = default;
};
using State = std::array<Item, layout::activeItem::count>;
template <class T> T& field(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
inline State capture(Address player) {
    State result;
    for (unsigned slot = 0; slot < result.size(); ++slot) {
        const auto offset = layout::player::primaryActive + slot * layout::activeItem::stride;
        result[slot].id = field<std::int32_t>(player, offset);
        result[slot].data =
            result[slot].id ? field<std::int32_t>(player, offset + layout::activeItem::data) : 0;
    }
    return result;
}
inline void restore(Address player, Address game, const State& state) {
    const auto current = capture(player);
    for (unsigned slot = 0; slot < state.size(); ++slot)
        if (state[slot].id != current[slot].id || (!state[slot].id && state[slot].data != 0) ||
            !compat::items::validActiveData(state[slot].id, state[slot].data))
            throw std::runtime_error("Active item data differs from restored inventory");
    for (unsigned slot = 0; slot < state.size(); ++slot) {
        if (state[slot].data == current[slot].data)
            continue;
        field<std::int32_t>(player, layout::player::primaryActive +
                                        slot * layout::activeItem::stride +
                                        layout::activeItem::data) = state[slot].data;
        // Invalidate only the changed slot's native icon key. Textures remain
        // owned by PlayerHUD and are rebuilt by its normal update/render.
        for (unsigned i = 0; game && i < layout::playerHud::count; ++i) {
            const auto hud = game + layout::game::playerHuds + i * layout::playerHud::size;
            if (field<Address>(hud, layout::playerHud::player) == player)
                field<int>(hud, layout::playerHud::activeItems +
                                    slot * layout::playerHud::activeStride) = 0;
        }
    }
}
} // namespace isaac::engine::j460::active_items

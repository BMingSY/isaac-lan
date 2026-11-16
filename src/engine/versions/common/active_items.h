#pragma once
#include "compat/items/active_data.h"
#include <array>
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::native_active_items {
using Address = std::uintptr_t;
struct Layout {
    unsigned primaryActive, stride, data, huds, hudStride, hudPlayer, hudActive, hudActiveStride;
};
inline constexpr unsigned hudCount = 8;
inline constexpr unsigned itemCount = 4;

static_assert(sizeof(Address) == 4);
struct Item {
    std::int32_t id = 0, data = 0;
    bool operator==(const Item&) const = default;
};
using State = std::array<Item, itemCount>;
template <class T> T& field(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
inline State capture(const Layout& layout, Address player) {
    State result;
    for (unsigned slot = 0; slot < result.size(); ++slot) {
        const auto offset = layout.primaryActive + slot * layout.stride;
        result[slot].id = field<std::int32_t>(player, offset);
        result[slot].data = result[slot].id ? field<std::int32_t>(player, offset + layout.data) : 0;
    }
    return result;
}
inline void restore(const Layout& layout, Address player, Address game, const State& state) {
    const auto current = capture(layout, player);
    for (unsigned slot = 0; slot < state.size(); ++slot)
        if (state[slot].id != current[slot].id || (!state[slot].id && state[slot].data != 0) ||
            !compat::items::validActiveData(state[slot].id, state[slot].data))
            throw std::runtime_error("Active item data differs from restored inventory");
    for (unsigned slot = 0; slot < state.size(); ++slot) {
        if (state[slot].data == current[slot].data)
            continue;
        field<std::int32_t>(player, layout.primaryActive + slot * layout.stride + layout.data) =
            state[slot].data;
        // Invalidate only the changed slot's native icon key. Textures remain
        // owned by PlayerHUD and are rebuilt by its normal update/render.
        for (unsigned i = 0; game && i < hudCount; ++i) {
            const auto hud = game + layout.huds + i * layout.hudStride;
            if (field<Address>(hud, layout.hudPlayer) == player)
                field<int>(hud, layout.hudActive + slot * layout.hudActiveStride) = 0;
        }
    }
}
} // namespace isaac::engine::native_active_items

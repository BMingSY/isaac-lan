#pragma once
#include "engine/versions/j460/layout.h"
#include <array>
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::j460::inventory_order {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
using State = std::array<std::int32_t, layout::player::inventorySlots>;
template <class T> T& field(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
inline State indices(Address player) {
    State result;
    for (unsigned i = 0; i < result.size(); ++i)
        result[i] = field<int>(player, layout::player::inventoryOrder + i * sizeof(int));
    return result;
}
inline State capture(Address player) {
    const auto first = field<Address>(player, layout::player::history);
    const auto last = field<Address>(player, layout::player::history + layout::vector::end);
    if (last < first || (last - first) % layout::historyItem::size ||
        (last - first) / layout::historyItem::size > layout::historyItem::maxEntries)
        throw std::runtime_error("Invalid player history vector");
    const auto count = (last - first) / layout::historyItem::size;
    const auto order = indices(player);
    State result{};
    for (unsigned i = 0; i < result.size(); ++i) {
        if (order[i] == -1)
            continue;
        if (order[i] < 0 || static_cast<unsigned>(order[i]) >= count)
            throw std::runtime_error("Invalid inventory history index");
        const auto entry = first + order[i] * layout::historyItem::size;
        if (field<bool>(entry, layout::historyItem::trinket))
            throw std::runtime_error("Inventory slot references a trinket");
        result[i] = field<int>(entry, layout::historyItem::id);
        if (!result[i])
            throw std::runtime_error("Inventory slot references an empty item");
    }
    return result;
}
inline void restore(Address player, Address game, const State& desired) {
    const auto local = capture(player), order = indices(player);
    State restored;
    restored.fill(-1);
    std::array<bool, layout::player::inventorySlots> used{};
    for (unsigned i = 0; i < desired.size(); ++i) {
        if (!desired[i])
            continue;
        for (unsigned j = 0; j < local.size(); ++j)
            if (!used[j] && local[j] == desired[i]) {
                used[j] = true;
                restored[i] = order[j];
                break;
            }
        if (restored[i] < 0)
            throw std::runtime_error("Inventory order differs from restored collectibles");
    }
    for (unsigned i = 0; i < local.size(); ++i)
        if (local[i] && !used[i])
            throw std::runtime_error("Inventory order omitted a collectible");
    if (restored == order)
        return;
    // Only reorder existing history indices. Native code retains ownership of
    // history, textures, item effects and the HUD's per-slot animation caches.
    for (unsigned i = 0; i < restored.size(); ++i)
        field<int>(player, layout::player::inventoryOrder + i * sizeof(int)) = restored[i];
    for (unsigned i = 0; game && i < layout::playerHud::count; ++i) {
        const auto hud = game + layout::game::playerHuds + i * layout::playerHud::size;
        if (field<Address>(hud, layout::playerHud::player) == player)
            field<bool>(hud, layout::playerHud::refreshFlags) = true;
    }
}
} // namespace isaac::engine::j460::inventory_order

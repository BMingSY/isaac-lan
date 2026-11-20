#pragma once
#include <array>
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::native_inventory_order {
using Address = std::uintptr_t;
struct Layout {
    unsigned order, history, historyStride, historyTrinket, historyId;
    unsigned huds, hudStride, hudPlayer, hudRefresh;
};
inline constexpr unsigned hudCount = 8;
inline constexpr unsigned inventorySlots = 16, maxHistoryEntries = 65536;

static_assert(sizeof(Address) == 4);
using State = std::array<std::int32_t, inventorySlots>;
template <class T> T& field(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
inline State indices(const Layout& layout, Address player) {
    State result;
    for (unsigned i = 0; i < result.size(); ++i)
        result[i] = field<int>(player, layout.order + i * sizeof(int));
    return result;
}
inline State capture(const Layout& layout, Address player) {
    const auto first = field<Address>(player, layout.history);
    const auto last = field<Address>(player, layout.history + sizeof(Address));
    if (last < first || (last - first) % layout.historyStride ||
        (last - first) / layout.historyStride > maxHistoryEntries)
        throw std::runtime_error("Invalid player history vector");
    const auto count = (last - first) / layout.historyStride;
    const auto order = indices(layout, player);
    State result{};
    for (unsigned i = 0; i < result.size(); ++i) {
        if (order[i] == -1)
            continue;
        if (order[i] < 0 || static_cast<unsigned>(order[i]) >= count)
            throw std::runtime_error("Invalid inventory history index");
        const auto entry = first + order[i] * layout.historyStride;
        if (field<bool>(entry, layout.historyTrinket))
            throw std::runtime_error("Inventory slot references a trinket");
        result[i] = field<int>(entry, layout.historyId);
        if (!result[i])
            throw std::runtime_error("Inventory slot references an empty item");
    }
    return result;
}
inline void restore(const Layout& layout, Address player, Address game, const State& desired) {
    const auto local = capture(layout, player), order = indices(layout, player);
    State restored;
    restored.fill(-1);
    std::array<bool, inventorySlots> used{};
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
        field<int>(player, layout.order + i * sizeof(int)) = restored[i];
    for (unsigned i = 0; game && i < hudCount; ++i) {
        const auto hud = game + layout.huds + i * layout.hudStride;
        if (field<Address>(hud, layout.hudPlayer) == player)
            field<bool>(hud, layout.hudRefresh) = true;
    }
}
} // namespace isaac::engine::native_inventory_order

#pragma once
#include <array>
#include <cstdint>

namespace isaac::compat::items {
struct CraftingBagState {
    std::array<std::uint8_t, 8> materials{};
    std::uint32_t preview = 0;
};
inline bool validCraftingBagState(const CraftingBagState& value) {
    bool empty = false;
    for (auto material : value.materials) {
        if (material > 29 || (empty && material))
            return false;
        empty |= material == 0;
    }
    return value.preview <= 65535 && (!empty || !value.preview);
}
} // namespace isaac::compat::items

#pragma once
#include <algorithm>
#include <cstdint>
#include <span>
#include <stdexcept>

namespace isaac::rooms {
inline void registerMapRoom(std::span<int, 507> offsets, unsigned& count, int dimension, int index,
                            int listIndex, std::span<const unsigned> cells) {
    if (dimension < 0 || dimension > 2 || index < 0 || index >= 169 || listIndex < 0 ||
        listIndex >= 507 || cells.empty() ||
        std::find(cells.begin(), cells.end(), static_cast<unsigned>(index)) == cells.end() ||
        std::any_of(cells.begin(), cells.end(), [](auto cell) { return cell >= 169; }))
        throw std::runtime_error("Invalid authoritative room map");
    for (auto cell : cells)
        offsets[dimension * 169 + cell] = listIndex;
    count = std::max(count, static_cast<unsigned>(listIndex + 1));
}
} // namespace isaac::rooms

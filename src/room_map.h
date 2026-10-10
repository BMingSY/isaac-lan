#pragma once
#include <algorithm>
#include <cstdint>
#include <optional>
#include <array>
#include <span>
#include <stdexcept>

namespace isaac::rooms {
inline bool validRoomRequest(int index, int dimension) {
    return dimension >= -1 && dimension <= 2 &&
           ((index >= -20 && index < 169) || index == -100 || index == -101);
}
inline std::optional<std::array<int, 2>>
canonicalRoomDestination(int requestedIndex, int descriptorIndex, int descriptorDimension) {
    // Native mirror/mineshaft aliases resolve across dimensions. Keep their
    // descriptor's real key on the wire and in the loaded-room table.
    const int index = requestedIndex >= 0 || requestedIndex == -100 || requestedIndex == -101
                          ? descriptorIndex
                          : requestedIndex;
    if (descriptorDimension < 0 || descriptorDimension > 2 || index < -20 || index >= 169 ||
        (requestedIndex >= 0 && index < 0) ||
        ((requestedIndex == -100 || requestedIndex == -101) && index < 0))
        return std::nullopt;
    return std::array<int, 2>{descriptorDimension, index};
}
inline void prepareDepartureMetadata(std::span<std::uint32_t, 3> destination,
                                     std::span<const std::uint32_t, 3> source) {
    // Level::ChangeRoom reads the departure descriptor/type before Room::Init
    // replaces them. A freshly allocated Room has neither; copying just these
    // scalars preserves the native cross-dimension checks without sharing any
    // room-owned containers or sprites.
    destination[1] = source[1];
    destination[2] = source[2];
}
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

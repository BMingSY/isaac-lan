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
inline void completeArrivalControls(int animation, bool& controlsEnabled, int nativeState) {
    // Native RoomTransition releases portal and minecart controls after
    // arrival. Per-actor transfers replace that process-wide completion.
    if ((animation == 0 && nativeState < 2) || animation == 11 || animation == 16 ||
        animation == 19)
        controlsEnabled = true;
}
inline bool gatherHomeCombat(int stage, int kind, bool dogma, unsigned audience,
                             unsigned connected) {
    return stage == 13 && kind == 1 && dogma && (audience & connected) != connected;
}
inline bool finalCombat(int stage, int kind, unsigned entityType, unsigned variant = 0) {
    if (stage == 11 && (kind == 0 || kind == 1))
        return entityType == 102 || entityType == 273 || entityType == 274 || entityType == 275;
    if (stage == 12)
        return entityType == 412;
    if (stage == 9 && kind == 0)
        return entityType == 406 || entityType == 407;
    if (stage == 8 && (kind == 4 || kind == 5))
        return entityType == 912;
    return stage == 13 && kind == 1 &&
           (entityType == 950 || entityType == 951 || (entityType == 960 && variant == 4));
}
inline bool escapeFollower(unsigned entityType, int dimension, bool escaping, bool lastOccupant) {
    return entityType == 867 && dimension == 1 && escaping && lastOccupant;
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

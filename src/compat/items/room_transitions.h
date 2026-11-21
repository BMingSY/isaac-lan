#pragma once
#include "compat/game_ids.h"
#include <cstdint>

namespace isaac::compat::items {
inline constexpr int blueRoomIndex = -16;
inline bool blueRoomTransition(int animation, int sourceDimension, int targetDimension) {
    constexpr int walk = 0;
    return animation == walk && (targetDimension < 0 || targetDimension == sourceDimension);
}
inline bool revivalTransition(int animation) {
    constexpr int ankh = 5, lazarus = 10, missingPoster = 14;
    return (animation >= ankh && animation <= lazarus) || animation == missingPoster;
}
inline bool floorFollower(unsigned type, unsigned variant, bool attached) {
    constexpr unsigned effect = 1000, redemption = 185;
    return type == effect && variant == redemption && attached;
}
inline bool roomFollower(unsigned type, unsigned variant, bool attached, unsigned subtype = 0,
                         std::uint64_t tearFlagsHigh = 0) {
    constexpr unsigned effect = 1000, spearOfDestiny = 83, halo = 123, salvationHalo = 6;
    constexpr unsigned puppyAngry = 0, puppyLarge = 1;
    constexpr unsigned ludovicoRing = 1;
    constexpr auto ludovicoTear = std::uint64_t{1} << 63; // TEAR_LUDOVICO, bit 127.
    // The angry body is an NPC parented to the owner's familiar. Both must
    // migrate together so native room entry retains its form and progress.
    // Laser subtype 1 is the controlled Ludovico ring; subtype 0 beams and
    // subtype 2 Tech X shots are transient and remain in their source room.
    return attached &&
           ((type == effect &&
             (variant == spearOfDestiny || (variant == halo && subtype == salvationHalo))) ||
            (type == ids::entity::bloodPuppy && (variant == puppyAngry || variant == puppyLarge)) ||
            (type == ids::entity::laser && subtype == ludovicoRing) ||
            (type == ids::entity::tear && (tearFlagsHigh & ludovicoTear)));
}
} // namespace isaac::compat::items

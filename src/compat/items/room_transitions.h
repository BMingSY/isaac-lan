#pragma once

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
} // namespace isaac::compat::items

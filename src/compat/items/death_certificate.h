#pragma once

namespace isaac::compat::items {
inline constexpr int deathCertificateAnimation = 20;
inline bool deathCertificateTransfer(int animation, int sourceDimension, int targetDimension) {
    // Both the native item entry and the delayed collectible return use this
    // animation. Doors and teleport cards within the annex remain individual.
    return animation == deathCertificateAnimation && (sourceDimension == 2 || targetDimension == 2);
}
inline bool deathCertificateTeleport(int animation, int sourceDimension) {
    return sourceDimension == 2 && (animation == 3 || animation == 11 || animation == 16);
}
} // namespace isaac::compat::items

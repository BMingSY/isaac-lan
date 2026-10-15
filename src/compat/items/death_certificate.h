#pragma once
#include <array>
#include <optional>

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
inline std::optional<std::array<float, 2>>
deathCertificateArrival(int animation, int sourceDimension, int targetDimension,
                        std::optional<std::array<float, 2>> residentPosition) {
    // Only the first party member runs native Room::Init. Later arrivals must
    // share a destination-space landing instead of keeping source-room pixels.
    // No resident means native initialization still owns the first landing.
    return deathCertificateTransfer(animation, sourceDimension, targetDimension) ? residentPosition
                                                                                 : std::nullopt;
}
} // namespace isaac::compat::items

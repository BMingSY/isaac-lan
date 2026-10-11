#pragma once

namespace isaac::compat::items {
// Each native query already includes the whole team's floor modifiers and
// damage penalties. Sharing room effects chooses a result; adding those
// complete results would count the same inventory/floor more than once.
constexpr float sharedRoomDealChance(float shared, float nativeRoom) {
    return nativeRoom > shared ? nativeRoom : shared;
}
} // namespace isaac::compat::items

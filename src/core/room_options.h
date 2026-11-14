#pragma once
#include <array>
#include <cstdint>
#include <string_view>

namespace isaac::roomOptions {
inline constexpr std::uint64_t friendlyFire = 1ull << 0;
inline constexpr std::uint64_t sharedClearCharge = 1ull << 1;
inline constexpr std::uint64_t lootRoll = 1ull << 2;
// Bits 3 and 4 belonged to the legacy special/all-room gathering toggles.
// Bits 5..33 select original RoomType values 1 (default)..29 (ultra secret).
inline constexpr std::uint64_t legacySpecialRoomGather = 1ull << 3;
inline constexpr std::uint64_t legacyAllRoomGather = 1ull << 4;
inline constexpr unsigned roomTypeCount = 29;
inline constexpr std::uint64_t firstRoomFlag = 1ull << 5;
inline constexpr std::uint64_t autoTeleport = ((1ull << roomTypeCount) - 1) * firstRoomFlag;
inline constexpr std::uint64_t known = friendlyFire | sharedClearCharge | lootRoll | autoTeleport;
struct Definition {
    std::uint64_t flag;
    std::string_view key, name, shortName;
};
inline constexpr std::array definitions{
    Definition{friendlyFire, "friendlyFire", "队友伤害", "友伤"},
    Definition{sharedClearCharge, "sharedClearCharge", "清房充能共享", "充能"},
    Definition{lootRoll, "lootRoll", "道具掷骰分配", "掷骰"},
    Definition{autoTeleport, "autoTeleport", "自动传送", "传送"}};
inline constexpr std::uint64_t migrateLegacy(std::uint64_t value) {
    if (value & legacyAllRoomGather)
        value |= autoTeleport;
    else if (value & legacySpecialRoomGather)
        value |= autoTeleport & ~firstRoomFlag;
    return value & ~(legacySpecialRoomGather | legacyAllRoomGather);
}
inline bool valid(std::uint64_t value) {
    return !(value & ~known);
}
} // namespace isaac::roomOptions

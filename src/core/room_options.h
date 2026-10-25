#pragma once
#include <array>
#include <cstdint>
#include <string_view>

namespace isaac::roomOptions {
inline constexpr std::uint32_t friendlyFire = 1u << 0;
inline constexpr std::uint32_t sharedClearCharge = 1u << 1;
inline constexpr std::uint32_t lootRoll = 1u << 2;
inline constexpr std::uint32_t specialRoomGather = 1u << 3;
inline constexpr std::uint32_t known =
    friendlyFire | sharedClearCharge | lootRoll | specialRoomGather;
struct Definition {
    std::uint32_t flag;
    std::string_view key, name, shortName;
};
inline constexpr std::array definitions{
    Definition{friendlyFire, "friendlyFire", "队友伤害", "友伤"},
    Definition{sharedClearCharge, "sharedClearCharge", "清房充能共享", "充能"},
    Definition{lootRoll, "lootRoll", "道具掷骰分配", "掷骰"},
    Definition{specialRoomGather, "specialRoomGather", "特殊房间集合", "集合"}};
inline bool valid(std::uint32_t value) {
    return !(value & ~known);
}
} // namespace isaac::roomOptions

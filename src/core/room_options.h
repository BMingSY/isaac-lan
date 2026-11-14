#pragma once
#include <array>
#include <cstdint>
#include <initializer_list>
#include <string_view>

namespace isaac::roomOptions {
inline constexpr std::uint64_t friendlyFire = 1ull << 0;
inline constexpr std::uint64_t sharedClearCharge = 1ull << 1;
inline constexpr std::uint64_t lootRoll = 1ull << 2;
// Bits 3 and 4 belonged to the legacy special/all-room gathering toggles.
// Bits 5..33 retain the original RoomType 1..29 wire/storage contract.
inline constexpr std::uint64_t legacySpecialRoomGather = 1ull << 3;
inline constexpr std::uint64_t legacyAllRoomGather = 1ull << 4;
inline constexpr unsigned roomTypeCount = 29;
inline constexpr std::uint64_t firstRoomFlag = 1ull << 5;
inline constexpr std::uint64_t roomTypeFlags = ((1ull << roomTypeCount) - 1) * firstRoomFlag;
// Portable game IDs used by this option contract, checked against the actual
// Lua RoomType enum by the native room-menu fixture. No native layout access.
enum class RoomType : unsigned {
    ordinary = 1,
    shop = 2,
    error = 3,
    treasure = 4,
    boss = 5,
    miniboss = 6,
    secret = 7,
    superSecret = 8,
    arcade = 9,
    curse = 10,
    challenge = 11,
    library = 12,
    sacrifice = 13,
    devil = 14,
    angel = 15,
    crawlspace = 16,
    bossRush = 17,
    cleanBedroom = 18,
    dirtyBedroom = 19,
    vault = 20,
    dice = 21,
    blackMarket = 22,
    greedExit = 23,
    planetarium = 24,
    teleporter = 25,
    teleporterExit = 26,
    secretExit = 27,
    blue = 28,
    ultraSecret = 29,
};
inline constexpr std::uint64_t roomFlag(RoomType type) {
    return firstRoomFlag << (static_cast<unsigned>(type) -
                             static_cast<unsigned>(RoomType::ordinary));
}
inline constexpr std::uint64_t roomFlags(std::initializer_list<RoomType> types) {
    std::uint64_t flags = 0;
    for (const auto type : types)
        flags |= roomFlag(type);
    return flags;
}
struct TeleportGroup {
    std::uint64_t flag;
    std::string_view key, name;
};
inline constexpr auto ordinaryRooms =
    roomFlags({RoomType::ordinary, RoomType::cleanBedroom, RoomType::dirtyBedroom,
               RoomType::greedExit, RoomType::secretExit, RoomType::blue});
inline constexpr std::array teleportGroups{
    TeleportGroup{ordinaryRooms, "ordinary", "普通房间"},
    TeleportGroup{roomFlags({RoomType::boss, RoomType::miniboss, RoomType::bossRush}), "boss",
                  "Boss 房"},
    TeleportGroup{roomFlags({RoomType::treasure, RoomType::planetarium, RoomType::vault,
                             RoomType::crawlspace}),
                  "treasure", "宝物房"},
    TeleportGroup{roomFlags({RoomType::shop, RoomType::blackMarket}), "shop", "商店"},
    TeleportGroup{roomFlags({RoomType::secret, RoomType::superSecret, RoomType::ultraSecret,
                             RoomType::error}),
                  "secret", "隐藏房"},
    TeleportGroup{roomFlags({RoomType::angel, RoomType::devil}), "deals", "天使／恶魔房"},
    TeleportGroup{roomFlags({RoomType::challenge, RoomType::curse, RoomType::sacrifice,
                             RoomType::library, RoomType::arcade, RoomType::dice}),
                  "special", "其他特殊房"}};
inline constexpr std::uint64_t autoTeleport = [] {
    std::uint64_t flags = 0;
    for (const auto& group : teleportGroups)
        flags |= group.flag;
    return flags;
}();
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
// A stored individual type selects its whole group. Unused teleporter types
// disappear; unrelated/unknown bits survive so callers can validate them.
inline constexpr std::uint64_t normalize(std::uint64_t value) {
    auto result = value & ~roomTypeFlags;
    for (const auto& group : teleportGroups)
        if (value & group.flag)
            result |= group.flag;
    return result;
}
inline constexpr std::uint64_t migrateLegacy(std::uint64_t value) {
    if (value & legacyAllRoomGather)
        value |= autoTeleport;
    else if (value & legacySpecialRoomGather)
        value |= autoTeleport & ~ordinaryRooms;
    return normalize(value & ~(legacySpecialRoomGather | legacyAllRoomGather));
}
inline bool valid(std::uint64_t value) {
    return !(value & ~known) && normalize(value) == value;
}
} // namespace isaac::roomOptions

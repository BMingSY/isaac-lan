#pragma once
#include "compat/game_ids.h"
#include <array>
#include <cstdint>
#include <limits>
#include <span>
#include <string_view>

namespace isaac::compat::challenges {
// The core run-rules regression checks this sentinel against the lobby contract.
inline constexpr std::uint16_t unrestrictedCharacter = 65535;
inline constexpr std::string_view blueBabyRoute = "blue_baby", lambRoute = "lamb";
struct Definition {
    std::uint16_t id, version, character;
    std::uint8_t difficulty;
    bool transient;
    std::string_view name, route;
    unsigned ending;
    int goalStage, goalStageType;
    bool nextBag;
    std::array<unsigned, 2> requiredAchievements;
    bool friendlyFire = false;
    bool roomOptionsLocked = false;
    bool largeFloor = false;
    bool nextPlayerShooting = false;
    bool deleteThis = false;
    bool crimeMode = false;
    unsigned rewardChallenge = 0;
    bool hidePlayerOutlines = false;

    unsigned nativeRewardChallenge(int stage) const {
        // I RULE! continues past the Lamb to Mega Satan. The Dark Room needs
        // its ordinary Lamb chest for the LAN trophy.
        return route == lambRoute && stage >= goalStage ? 0 : rewardChallenge;
    }
};
inline constexpr std::array definitions{
    Definition{
        1001,
        2,
        ids::player::cainB,
        0,
        true,
        "恶魔形态",
        lambRoute,
        6,
        ids::stage::chestOrDarkRoom,
        ids::stageType::original,
        true,
        {78, 476},
    },
    Definition{
        1002,
        1,
        unrestrictedCharacter,
        0,
        true,
        "运气游戏",
        "mom",
        ids::ending::epilogue,
        ids::stage::chapterThreeSecond,
        ids::stageType::original,
        false,
        {},
    },
    Definition{
        1003,
        3,
        ids::player::isaac,
        0,
        true,
        "吃鸡",
        "battle_royale",
        ids::ending::epilogue,
        ids::stage::chapterThreeSecond,
        ids::stageType::original,
        false,
        {},
        true,
        true,
    },
    Definition{
        1004,
        1,
        unrestrictedCharacter,
        0,
        true,
        "超大房间",
        "heart",
        ids::ending::epilogue,
        ids::stage::chapterFourSecond,
        ids::stageType::original,
        false,
        {4, 0},
        false,
        false,
        true,
    },
    Definition{
        1005,
        1,
        unrestrictedCharacter,
        0,
        true,
        "你的准星",
        "mom",
        ids::ending::epilogue,
        ids::stage::chapterThreeSecond,
        ids::stageType::original,
        false,
        {},
        false,
        false,
        false,
        true,
    },
    Definition{
        .id = 1006,
        .version = 1,
        .character = unrestrictedCharacter,
        .difficulty = 0,
        .transient = true,
        .name = "挑战45",
        .route = blueBabyRoute,
        .ending = ids::ending::epilogue,
        .goalStage = ids::stage::chestOrDarkRoom,
        .goalStageType = ids::stageType::wrathOfTheLamb,
        .nextBag = false,
        .requiredAchievements = {},
        .deleteThis = true,
        .rewardChallenge = ids::challenge::deleteThis,
    },
    Definition{
        .id = 1007,
        .version = 1,
        .character = unrestrictedCharacter,
        .difficulty = 0,
        .transient = true,
        .name = "捕风捉影",
        .route = lambRoute,
        .ending = ids::ending::epilogue,
        .goalStage = ids::stage::chestOrDarkRoom,
        .goalStageType = ids::stageType::original,
        .nextBag = false,
        .requiredAchievements = {},
        .rewardChallenge = ids::challenge::iRule,
        .hidePlayerOutlines = true,
    },
    Definition{
        .id = 1008,
        .version = 3,
        .character = unrestrictedCharacter,
        .difficulty = 0,
        .transient = true,
        .name = "幺幺幺九",
        .route = blueBabyRoute,
        .ending = ids::ending::epilogue,
        .goalStage = ids::stage::chestOrDarkRoom,
        .goalStageType = ids::stageType::wrathOfTheLamb,
        .nextBag = false,
        .requiredAchievements = {},
        .crimeMode = true,
        .rewardChallenge = ids::challenge::deleteThis,
    },
};
inline const Definition* find(unsigned id) {
    for (const auto& definition : definitions)
        if (definition.id == id)
            return &definition;
    return nullptr;
}
inline int nextSeat(unsigned slot, unsigned players) {
    if (players < 2 || players > static_cast<unsigned>(std::numeric_limits<int>::max()) ||
        slot >= players)
        return -1;
    return static_cast<int>((slot + 1) % players);
}
inline bool available(const Definition& definition, std::span<const std::uint8_t> achievements) {
    for (const auto id : definition.requiredAchievements)
        if (id && (id >= achievements.size() || !achievements[id]))
            return false;
    return true;
}
} // namespace isaac::compat::challenges

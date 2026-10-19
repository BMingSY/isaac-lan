#pragma once
#include "compat/game_ids.h"
#include <array>
#include <cstdint>
#include <span>
#include <string_view>

namespace isaac::compat::challenges {
// The core run-rules regression checks this sentinel against the lobby contract.
inline constexpr std::uint16_t unrestrictedCharacter = 65535;
struct Definition {
    std::uint16_t id, version, character;
    std::uint8_t difficulty;
    bool transient;
    std::string_view name, route;
    unsigned ending;
    int goalStage, goalStageType;
    bool nextBag;
    std::array<unsigned, 2> requiredAchievements;
};
inline constexpr std::array definitions{
    Definition{
        1001,
        2,
        ids::player::cainB,
        0,
        true,
        "恶魔形态",
        "lamb",
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
};
inline const Definition* find(unsigned id) {
    for (const auto& definition : definitions)
        if (definition.id == id)
            return &definition;
    return nullptr;
}
inline int nextSeat(unsigned slot, unsigned players) {
    return players >= 2 && players <= 4 && slot < players ? (slot + 1) % players : -1;
}
inline bool available(const Definition& definition, std::span<const std::uint8_t> achievements) {
    for (const auto id : definition.requiredAchievements)
        if (id && (id >= achievements.size() || !achievements[id]))
            return false;
    return true;
}
} // namespace isaac::compat::challenges

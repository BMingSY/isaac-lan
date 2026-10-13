#pragma once
#include "compat/game_ids.h"
#include <array>
#include <cstdint>
#include <span>
#include <string_view>

namespace isaac::compat::challenges {
struct Definition {
    std::uint16_t id, version, character;
    std::uint8_t difficulty;
    bool transient;
    std::string_view name, route, description;
    unsigned ending;
    int goalStage, goalStageType;
    bool nextBag;
    std::array<unsigned, 2> requiredAchievements;
};
inline constexpr std::array definitions{
    Definition{1001,
               2,
               ids::player::cainB,
               0,
               true,
               "恶魔形态",
               "lamb",
               "2～4 人 · 全员里该隐\n只能看下一位的材料与预览\n羔羊奖杯 · "
               "需解锁底片与里该隐\n不支持续玩 · 支持掉线重连",
               6,
               ids::stage::chestOrDarkRoom,
               ids::stageType::original,
               true,
               {78, 476}},
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
        if (id >= achievements.size() || !achievements[id])
            return false;
    return true;
}
} // namespace isaac::compat::challenges

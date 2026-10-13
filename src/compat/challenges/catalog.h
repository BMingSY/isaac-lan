#pragma once
#include "compat/game_ids.h"
#include <array>
#include <cstdint>
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
};
inline constexpr std::array definitions{
    Definition{1001, 1, ids::player::cainB, 0, true, "盲袋接力", "lamb",
               "2～4 人 · 全员里该隐\n只能看下一位的材料与预览\n终点：羔羊 · "
               "领取奖杯完成\n不支持续玩 · 支持掉线重连",
               6, ids::stage::chestOrDarkRoom, ids::stageType::original, true},
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
} // namespace isaac::compat::challenges

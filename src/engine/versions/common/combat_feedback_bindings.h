#pragma once
#include <cstdint>

namespace isaac::engine::native_combat_feedback {
inline constexpr unsigned colorBytes = 44;
struct EntityLayout {
    unsigned type, initSeed, index, sprite, spriteColor, damageQueue, damageRecordSize;
};
struct RoomLayout {
    unsigned dimension, index, entities, renderArray, data, count;
};
struct Bindings {
    std::uint32_t damage, setColor, colorReturn, drain, game;
    EntityLayout entity;
    RoomLayout room;
    unsigned sourceEntity;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_combat_feedback

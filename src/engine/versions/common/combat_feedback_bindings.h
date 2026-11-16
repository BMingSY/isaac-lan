#pragma once
#include <cstdint>

namespace isaac::engine::native_combat_feedback {
inline constexpr unsigned colorBytes = 44;
struct EntityLayout {
    unsigned type, initSeed, index, sprite, spriteColor, damageQueue, damageRecordSize, active;
};
struct RoomLayout {
    unsigned dimension, index, entities, renderArray, data, count;
};
struct Bindings {
    std::uint32_t damage, setColor, colorReturn, drain, game;
    EntityLayout entity;
    RoomLayout room;
    unsigned sourceEntity;
    std::uintptr_t (*npc)(std::uintptr_t image, std::uintptr_t entity);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_combat_feedback

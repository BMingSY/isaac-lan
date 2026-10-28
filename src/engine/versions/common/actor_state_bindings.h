#pragma once
#include <array>
namespace isaac::engine::native_actor_state {
struct Bindings {
    unsigned game, getHud;
    struct Entity {
        unsigned sprite, type;
    } entity;
    struct Player {
        unsigned type, costumes, costumeStride, chargeSprites, spriteStride;
        std::array<unsigned, 3> sprites;
        unsigned pockets, bagMaterials, bagPreview, poopMana, poopQueue;
    } player;
    struct Hud {
        unsigned partStride, bagDirty;
    } hud;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_actor_state

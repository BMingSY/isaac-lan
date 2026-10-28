#pragma once
#include <array>
namespace isaac::engine::native_entity_pose {
inline constexpr unsigned weaponSlots = 5, chargeValues = 3, costumeLayers = 15;
inline constexpr unsigned shadowValues = 4, maxCostumes = 4096, maxPath = 1024;
struct Bindings {
    struct Entity {
        unsigned sprite, type;
        std::array<unsigned, shadowValues> shadow;
    } entity;
    struct Player {
        std::array<unsigned, 2> poseFlags;
        unsigned blinkTime, damageCooldown, nightLightAngle, weapons;
        unsigned costumesBegin, costumesEnd, costumeStride, costumePath;
        unsigned layers, layerStride, costumeIndex, layerId, priority, body;
    } player;
    struct Weapon {
        unsigned kind, modifiers, maxChargeMethod;
        std::array<unsigned, chargeValues> charge;
    } weapon;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_entity_pose

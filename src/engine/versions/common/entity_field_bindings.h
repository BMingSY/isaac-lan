#pragma once
#include <cstdint>

namespace isaac::engine::native_entity_fields {
inline constexpr unsigned colorBytes = 44;
struct Bindings {
    struct Entries {
        std::uint32_t entityLuaSetSize, entityLuaSetColor, tearSetHeight, tearSetScale,
            pickupSetPrice;
    } entry;
    std::uint32_t game;
    struct Layout {
        struct Entity {
            unsigned type, variant, subtype, initSeed, positionX, velocity, friction, hitPoints,
                maxHitPoints, collisionDamage, visible, flipX, depthOffset, mass, size,
                spriteRotation, spriteOffset, spriteScale, createdFrame, flags, color, sprite,
                active, damageVtableSlot;
        } entity;
        struct Sprite {
            unsigned path, animation, overlay, flipX, flipY, rotation, scale, offset, color, size;
        } sprite;
        struct Color {
            unsigned red, green, blue, alpha, redOffset, greenOffset, blueOffset, size,
                colorizeChannels, colorize;
        } color;
        struct Tear {
            unsigned fallingAcceleration, fallingSpeed, height, rotation, scale, waitFrames;
        } tear;
        struct Effect {
            unsigned state, timeout, lifeSpan, rotation, scale, minRadius, maxRadius;
        } effect;
        struct Familiar {
            unsigned state, fireCooldown, headFrameDelay, moveDirection, shootDirection,
                lastDirection, orbitAngleOffset, orbitLayer, orbitSpeed;
        } familiar;
        struct Pickup {
            unsigned autoUpdatePrice, charge, optionsIndex, price, shopItemId, state, timeout,
                touched, wait;
        } pickup;
        struct String {
            unsigned size, capacity, inlineCapacity;
        } string;
        struct AnimationState {
            unsigned data, frame;
        } animationState;
        struct Npc {
            unsigned boss;
        } npc;
        struct Game {
            unsigned frame;
        } game;
    } layout;
    int minimumShopItemId, maximumShopItemId;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_entity_fields

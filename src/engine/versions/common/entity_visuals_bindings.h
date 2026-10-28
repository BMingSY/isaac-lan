#pragma once
namespace isaac::engine::native_visuals {
inline constexpr unsigned bodySprites = 5, bodyLayers = 4;
inline constexpr unsigned maxTetherPoints = 256, maxTetherCapacity = 4096;
inline constexpr unsigned maxTetherDataBytes = 512;
struct Bindings {
    unsigned entityType, entitySprite, spriteSize, extraData, prepareNeedle, renderTether;
    struct Body {
        unsigned dataVtable, sprites, layers;
    } body;
    struct Tether {
        unsigned dataVtable, points, capacity, first, count, sprite, size;
    } tether;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_visuals

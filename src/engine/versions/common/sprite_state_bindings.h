#pragma once
#include <array>
#include <optional>

namespace isaac::engine::native_sprite {
inline constexpr unsigned colorValues = 22, layerValues = 18, blendValues = 5, layerFlags = 3;
struct Bindings {
    unsigned resetAnimation;
    struct String {
        unsigned length, capacity, inlineCapacity;
    } string;
    struct Sprite {
        unsigned size, animation, overlay, shadow, colors, speed, flags, overlayFirst;
        unsigned layers, layerCount;
    } sprite;
    struct Layer {
        unsigned stride, data, id, path;
        std::array<unsigned, layerFlags> booleans;
        std::array<unsigned, layerValues> numbers;
        // The canonical fifth blend word is absent in J835 and must be zero.
        std::array<std::optional<unsigned>, blendValues> blend;
        unsigned flags;
    } layer;
    struct Animation {
        unsigned data, layerFrames, nullFrames, frame, playing, events, previousEvents;
    } animation;
    struct AnimationData {
        unsigned layers, layerCount, nulls, nullCount, layerMap, totalFrames, name;
    } data;
    struct AnimationLayer {
        unsigned stride, id, frameCount, nullFrameCount;
    } animationLayer;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_sprite

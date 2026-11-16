#pragma once
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>

namespace isaac::engine::native_entity_size {
struct Layout {
    unsigned configuration, sizeMultiplier, gridCollisionPoints;
    unsigned vectorBegin, vectorEnd, vectorCapacity;
};
struct Multiplier {
    float x, y;
};
inline constexpr float configurationMultiplier = -1.0f;

template <class T> T read(std::uintptr_t entity, unsigned offset) {
    return *reinterpret_cast<const T*>(entity + offset);
}
template <class DefaultSetter, class ExplicitSetter>
void restore(const Layout& layout, std::uintptr_t entity, float radius, DefaultSetter defaults,
             ExplicitSetter explicitSize) {
    if (!std::isfinite(radius))
        throw std::runtime_error("Invalid entity size");
    auto* object = reinterpret_cast<void*>(entity);
    if (read<std::uintptr_t>(entity, layout.configuration)) {
        defaults(object, radius);
        return;
    }
    // The engine can keep a live entity without an XML configuration. Its Lua
    // Size property requests XML defaults even for an unchanged radius. Use
    // the existing shape instead; native SetSize still rebuilds its own vector.
    const auto multiplier = read<Multiplier>(entity, layout.sizeMultiplier);
    const auto points = entity + layout.gridCollisionPoints;
    const auto begin = read<std::uintptr_t>(points, layout.vectorBegin);
    const auto end = read<std::uintptr_t>(points, layout.vectorEnd);
    const auto capacity = read<std::uintptr_t>(points, layout.vectorCapacity);
    constexpr auto pointBytes = sizeof(Multiplier);
    if (!std::isfinite(multiplier.x) || !std::isfinite(multiplier.y) ||
        (multiplier.x == configurationMultiplier && multiplier.y == configurationMultiplier) ||
        begin > end || end > capacity || (!begin && (end || capacity)) ||
        (end - begin) % pointBytes || (capacity - begin) % pointBytes ||
        (end - begin) / pointBytes > static_cast<unsigned>(std::numeric_limits<int>::max()))
        throw std::runtime_error("Invalid entity collision shape");
    explicitSize(object, radius, multiplier, static_cast<int>((end - begin) / pointBytes));
}
} // namespace isaac::engine::native_entity_size

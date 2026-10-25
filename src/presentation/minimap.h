#pragma once
#include <algorithm>
#include <cmath>
#include <optional>

namespace isaac::presentation {
struct MapRect {
    float left, top, right, bottom;
};
struct MinimapView {
    // Screen-space center of grid cell (0, 0), pitch and visible texture crop.
    float x, y, cellWidth, cellHeight;
    MapRect clip;
    float alpha;
    int dimension;
};
inline std::optional<MinimapView> projectMinimap(MapRect source, MapRect destination, float originX,
                                                 float originY, float pitchX, float pitchY,
                                                 float alpha, int dimension) {
    for (float value :
         {source.left, source.top, source.right, source.bottom, destination.left, destination.top,
          destination.right, destination.bottom, originX, originY, pitchX, pitchY, alpha})
        if (!std::isfinite(value))
            return std::nullopt;
    if (source.right <= source.left || source.bottom <= source.top ||
        destination.right <= destination.left || destination.bottom <= destination.top ||
        pitchX <= 0 || pitchY <= 0 || alpha <= 0)
        return std::nullopt;
    const float scaleX = (destination.right - destination.left) / (source.right - source.left);
    const float scaleY = (destination.bottom - destination.top) / (source.bottom - source.top);
    return MinimapView{destination.left + (originX - source.left) * scaleX,
                       destination.top + (originY - source.top) * scaleY,
                       pitchX * scaleX,
                       pitchY * scaleY,
                       destination,
                       std::clamp(alpha, 0.0f, 1.0f),
                       dimension};
}
} // namespace isaac::presentation

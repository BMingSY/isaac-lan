#pragma once
#include <cstdint>
#include "net/protocol.h"
namespace isaac::engine::native_frontend_hud {
struct Point {
    float x, y;
};
// Preserve native layout measurements when the original glyphs are hidden.
inline constexpr Point outsideViewport{-32768.f, -32768.f};
struct Filters {
    unsigned hearts = 0, activeItem = 0, pocketItems = 0;
};
extern Filters filters;
inline bool hidden(unsigned mask, int controller, int localSlot) {
    constexpr unsigned local = 1, teammates = 2;
    return localSlot >= 0 && controller >= 1 && controller <= static_cast<int>(lan::maxPlayers) &&
           (mask & (controller == localSlot + 1 ? local : teammates));
}
using HeartRenderer = bool (*)(unsigned viewIndex, Point position, float scale);
void setHeartRenderer(HeartRenderer renderer);
bool replaceHearts(void* hud, Point position, float scale);
bool hideActiveItem(void* hud);
bool install(std::uintptr_t image);
} // namespace isaac::engine::native_frontend_hud

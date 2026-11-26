#pragma once
#include "net/protocol.h"
#include <array>
#include <cstdint>
#include <string_view>
namespace isaac::engine::native_frontend_hud {
struct Point {
    float x, y;
};
// Preserve native layout measurements when the original glyphs are hidden.
inline constexpr Point outsideViewport{-32768.f, -32768.f};
enum class Component : unsigned { hearts, activeItem, trinket, pocketItems, count };
inline constexpr std::array<std::string_view, static_cast<unsigned>(Component::count)> names{
    "hearts", "activeItem", "trinket", "pocketItems"};
struct Filter {
    unsigned hidden = 0, rendered = 0;
};
struct Draw {
    Point position;
    float scale, alpha = 1;
    int slot = -1;
};
using Renderer = bool (*)(Component, unsigned viewIndex, const Draw&);
void configure(Component component, Filter filter, Renderer renderer);
void resetFilters();
bool replace(Component component, void* hud, const Draw& draw);
bool install(std::uintptr_t image);
} // namespace isaac::engine::native_frontend_hud

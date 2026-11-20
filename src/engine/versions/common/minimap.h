#pragma once
#include "net/protocol.h"
#include "presentation/minimap.h"
#include <array>
#include <cstdint>
#include <vector>
namespace isaac::engine::native_minimap {
struct Location {
    int index = -1, dimension = 0;
};
struct Marker {
    float x, y;
    int slot;
    float alpha;
};
// Native adapters pass borrowed draw parameters; only projected scalar values survive the call.
void observeTexture(std::uintptr_t texture, const float* quad, bool pixels,
                    const float* destination, float alpha);
bool install(std::uintptr_t image, void (*onRender)());
void setPlayers(bool active, int count, const std::array<Location, lan::maxPlayers>& positions);
void prepareView();
const std::vector<presentation::MinimapView>& minimapViews();
const std::vector<Marker>& frameMarkers();
void clearMarkers();
} // namespace isaac::engine::native_minimap

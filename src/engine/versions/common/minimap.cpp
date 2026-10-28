#include "engine/versions/common/minimap.h"
#include "engine/versions/common/minimap_bindings.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include "core/level_grid.h"
#include <MinHook.h>
namespace isaac::engine::native_minimap {
namespace {
std::uintptr_t image = 0, activeMap = 0, anchorOwner = 0;
void (*onRender)() = nullptr;
bool installed = false, prepared = false;
int count = 0;
std::array<Location, lan::maxPlayers> positions;
std::array<Location, 2> mapAnchors;
std::vector<Marker> markers;
std::vector<presentation::MinimapView> mapViews;
using MapRender = void(__attribute__((thiscall)) *)(void*);
MapRender originalMapRender = nullptr, originalMapCache = nullptr, originalMinimapUpdate = nullptr;
template <class T> T& read(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
void selectAnchors(std::uintptr_t map) {
    if (map != anchorOwner) {
        mapAnchors = {};
        anchorOwner = map;
    }
}
void __attribute__((fastcall)) mapCache(void* config, void*) {
    rooms::withView([&] {
        const auto game = read<std::uintptr_t>(image, bindings.game);
        if (!game)
            return;
        const auto offset =
            reinterpret_cast<std::uintptr_t>(config) - (game + bindings.gameLayout.minimap);
        selectAnchors(game + bindings.gameLayout.minimap);
        if (runtime::localViewSlot() >= 0) {
            // CacheMap switches targets before flushing. Native menu/scene work
            // already queued for the current target must stay on that target.
            using Flush = void(__attribute__((thiscall))*)(void*, bool);
            reinterpret_cast<Flush>(image + bindings.entry.flush)(
                reinterpret_cast<void*>(image + bindings.renderer), false);
        }
        rooms::withMapPickups([&] { originalMapCache(config); });
        if (offset == bindings.minimapLayout.small || offset == bindings.minimapLayout.large)
            mapAnchors[offset == bindings.minimapLayout.small ? 0 : 1] = {
                read<int>(game, bindings.gameLayout.roomIndex),
                read<int>(game, bindings.gameLayout.dimension)};
    });
}
void __attribute__((fastcall)) minimapUpdate(void* map, void*) {
    rooms::withView([&] { originalMinimapUpdate(map); });
}
void __attribute__((fastcall)) minimapRender(void* map, void*) {
    struct Restore {
        std::uintptr_t value = activeMap;
        ~Restore() {
            activeMap = value;
        }
    } restore;
    activeMap = reinterpret_cast<std::uintptr_t>(map);
    const auto texture = activeMap
                             ? read<std::uintptr_t>(activeMap, bindings.minimapLayout.small +
                                                                   bindings.mapConfigLayout.texture)
                             : 0;
    if (texture)
        ensureTextureHook(image, texture);
    originalMapRender(map);
    activeMap = restore.value;
    if (prepared && onRender)
        onRender();
}
} // namespace
void observeTexture(std::uintptr_t texture, const float* quad, bool pixels,
                    const float* destination, float alpha) {
    if (activeMap && prepared && quad && destination && std::isfinite(alpha)) {
        const auto source = texture;
        for (unsigned offset : {bindings.minimapLayout.small, bindings.minimapLayout.large})
            if (source ==
                read<std::uintptr_t>(activeMap, offset + bindings.mapConfigLayout.texture)) {
                const auto config = activeMap + offset;
                const auto anchor = mapAnchors[offset == bindings.minimapLayout.small ? 0 : 1];
                const auto* q = static_cast<const float*>(quad);
                const auto* dest = static_cast<const float*>(destination);
                const float width =
                    pixels ? 1.0f
                           : static_cast<float>(read<int>(source, bindings.textureLayout.width));
                const float height =
                    pixels ? 1.0f
                           : static_cast<float>(read<int>(source, bindings.textureLayout.height));
                const float left = q[0] * width, top = q[1] * height, dx = (q[2] - q[0]) * width,
                            dy = (q[5] - q[1]) * height;
                if (dx == 0 || dy == 0 || anchor.index < 0 || anchor.index >= level_grid::cellCount)
                    continue;
                const float pitchX = read<float>(config, bindings.mapConfigLayout.cellWidth) +
                                     read<float>(config, bindings.mapConfigLayout.cellSpacing);
                const float pitchY = read<float>(config, bindings.mapConfigLayout.cellHeight) +
                                     read<float>(config, bindings.mapConfigLayout.cellSpacing);
                // Native minimaps use axis-aligned texture quads. Export only
                // this frame's actual draw, including cropping and TAB fades.
                if (dest[4] == dest[0] && dest[3] == dest[1]) {
                    const auto view = presentation::projectMinimap(
                        {left, top, left + dx, top + dy}, {dest[0], dest[1], dest[2], dest[5]},
                        read<float>(config, bindings.mapConfigLayout.anchorX) -
                            (anchor.index % level_grid::width) * pitchX,
                        read<float>(config, bindings.mapConfigLayout.anchorY) -
                            (anchor.index / level_grid::width) * pitchY,
                        pitchX, pitchY, alpha, anchor.dimension);
                    if (view)
                        mapViews.push_back(*view);
                }
                for (int slot = 0; slot < count && slot < static_cast<int>(lan::maxPlayers);
                     ++slot) {
                    const auto p = positions[slot];
                    if (p.index < 0 || p.index >= level_grid::cellCount ||
                        p.dimension != anchor.dimension)
                        continue;
                    const float x =
                        read<float>(config, bindings.mapConfigLayout.anchorX) +
                        (p.index % level_grid::width - anchor.index % level_grid::width) *
                            (read<float>(config, bindings.mapConfigLayout.cellWidth) +
                             read<float>(config, bindings.mapConfigLayout.cellSpacing));
                    const float y =
                        read<float>(config, bindings.mapConfigLayout.anchorY) +
                        (p.index / level_grid::width - anchor.index / level_grid::width) *
                            (read<float>(config, bindings.mapConfigLayout.cellHeight) +
                             read<float>(config, bindings.mapConfigLayout.cellSpacing));
                    const float u = (x - left) / dx, v = (y - top) / dy;
                    if (!std::isfinite(u) || !std::isfinite(v) || u < 0 || u > 1 || v < 0 || v > 1)
                        continue;
                    const float screenX =
                                    dest[0] + u * (dest[2] - dest[0]) + v * (dest[4] - dest[0]),
                                screenY =
                                    dest[1] + u * (dest[3] - dest[1]) + v * (dest[5] - dest[1]);
                    if (std::isfinite(screenX) && std::isfinite(screenY))
                        markers.push_back({screenX, screenY, slot, std::clamp(alpha, 0.0f, 1.0f)});
                }
            }
    }
}
void prepareView() {
    mapViews.clear();
    if (!originalMapCache || runtime::localViewSlot() < 0)
        return;
    // CacheMap clears an offscreen target and flushes the shared native draw
    // queue. Rebuilding it inside Minimap::Render would consume the room's
    // pending scene into that texture, leaving a black scene and map smears.
    // Resolve the local view before Game::Render starts submitting that scene.
    rooms::withView([&] {
        const auto game = read<std::uintptr_t>(image, bindings.game);
        if (!game)
            return;
        selectAnchors(game + bindings.gameLayout.minimap);
        for (unsigned i = 0; i < 2; ++i)
            if (mapAnchors[i].index != read<int>(game, bindings.gameLayout.roomIndex) ||
                mapAnchors[i].dimension != read<int>(game, bindings.gameLayout.dimension))
                mapCache(reinterpret_cast<void*>(
                             game + bindings.gameLayout.minimap +
                             (i ? bindings.minimapLayout.large : bindings.minimapLayout.small)),
                         nullptr);
    });
}
const std::vector<presentation::MinimapView>& minimapViews() {
    return mapViews;
}
const std::vector<Marker>& frameMarkers() {
    return markers;
}
void clearMarkers() {
    markers.clear();
}
void setPlayers(bool active, int players, const std::array<Location, lan::maxPlayers>& locations) {
    prepared = active;
    count = std::clamp(players, 0, static_cast<int>(lan::maxPlayers));
    positions = locations;
    if (!active) {
        anchorOwner = 0;
        mapAnchors = {};
        markers.clear();
        mapViews.clear();
    }
}
bool install(std::uintptr_t base, void (*render)()) {
    if (!base || installed)
        return false;
    struct Hook {
        unsigned rva;
        void* detour;
        void** original;
    };
    const std::array<Hook, 3> hooks{{
        {bindings.entry.update, reinterpret_cast<void*>(minimapUpdate),
         reinterpret_cast<void**>(&originalMinimapUpdate)},
        {bindings.entry.render, reinterpret_cast<void*>(minimapRender),
         reinterpret_cast<void**>(&originalMapRender)},
        {bindings.entry.cache, reinterpret_cast<void*>(mapCache),
         reinterpret_cast<void**>(&originalMapCache)},
    }};
    image = base;
    unsigned created = 0;
    const auto rollback = [&] {
        for (unsigned i = 0; i < created; ++i) {
            MH_RemoveHook(reinterpret_cast<void*>(image + hooks[i].rva));
            *hooks[i].original = nullptr;
        }
        image = 0;
    };
    for (const auto& hook : hooks) {
        if (MH_CreateHook(reinterpret_cast<void*>(image + hook.rva), hook.detour, hook.original) !=
            MH_OK) {
            rollback();
            return false;
        }
        ++created;
    }
    for (const auto& hook : hooks)
        if (MH_EnableHook(reinterpret_cast<void*>(image + hook.rva)) != MH_OK) {
            rollback();
            return false;
        }
    onRender = render;
    installed = true;
    return true;
}
} // namespace isaac::engine::native_minimap

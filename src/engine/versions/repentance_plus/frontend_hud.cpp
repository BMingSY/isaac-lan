#include "engine/versions/common/frontend_hud_bindings.h"
#include "engine/versions/common/frontend_hud.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
namespace isaac::engine::native_frontend_hud {
namespace backend = repentance_plus;
namespace layout = backend::layout;
namespace {
using Hearts = Point*(__attribute__((thiscall)) *)(void*, Point*, void*, int, float, Point);
Hearts originalHearts = nullptr;
Point* __attribute__((fastcall)) drawHearts(void* hud, void*, Point* extent, void* sprite,
                                            int layoutId, float scale, Point pos) {
    constexpr int compactTwins = 3;
    constexpr float secondRow = 34.f;
    Point anchor = pos;
    if (hud && layoutId == compactTwins &&
        *reinterpret_cast<short*>(reinterpret_cast<std::uintptr_t>(hud) +
                                  layout::playerHud::index) >=
            static_cast<int>(layout::playerHud::count / 2))
        anchor.y += secondRow;
    return originalHearts(hud, extent, sprite, layoutId, scale,
                          replaceHearts(hud, anchor, scale) ? outsideViewport : pos);
}
using ActiveItem = void(__attribute__((thiscall)) *)(void*, unsigned, const Point*, int, float,
                                                     float, bool);
ActiveItem originalActiveItem = nullptr;
void __attribute__((fastcall)) drawActiveItem(void* hud, void*, unsigned slot, const Point* pos,
                                              int layoutId, float size, float alpha, bool overlay) {
    if (!hideActiveItem(hud))
        originalActiveItem(hud, slot, pos, layoutId, size, alpha, overlay);
}
} // namespace
const DrawHook activeItemHook{reinterpret_cast<void*>(drawActiveItem),
                              reinterpret_cast<void**>(&originalActiveItem)};
const DrawHook heartHook{reinterpret_cast<void*>(drawHearts),
                         reinterpret_cast<void**>(&originalHearts)};
const Bindings bindings{
    backend::globals::game,
    layout::game::players,
    layout::hud::history,
    {backend::entry::frontendStatHUDGetPlayerId, backend::entry::frontendStatHUDReset,
     backend::entry::historyHUDGetPlayerId, backend::entry::historyHUDRecomputeAll,
     backend::entry::playerHUDReset, backend::entry::hUDUpdate, backend::entry::hUDPostUpdate,
     backend::entry::hUDRender, backend::entry::playerHudRenderHearts,
     backend::entry::playerHudRenderActiveItem},
    {layout::statHud::player, layout::statHud::cacheStride, layout::statHud::cacheCount},
    {layout::player::controller, layout::player::index, layout::player::twin, layout::player::type},
    {layout::entity::parent, layout::entity::active},
    {layout::playerHud::size, layout::playerHud::refreshFlags, layout::playerHud::refreshAll}};
} // namespace isaac::engine::native_frontend_hud

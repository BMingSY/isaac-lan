#include "engine/versions/common/crafting_hud_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_crafting_hud {
namespace {
namespace layout = repentance::layout;
template <class T> T at(std::uintptr_t address, unsigned offset) {
    return *reinterpret_cast<const T*>(address + offset);
}
bool placePocket(std::uintptr_t image, std::uintptr_t hud, std::uintptr_t, float width,
                 float height, PocketLayout& pocket) {
    const auto manager = image ? at<std::uintptr_t>(image, repentance::globals::manager) : 0;
    if (!manager)
        return false;
    // HUD::Render at 0x505ece uses the current option directly. No Repentance+ HUD
    // offset or layout object exists at this boundary.
    const float margin =
        1.0f - at<float>(manager, layout::manager::options + layout::options::hudOffset);
    constexpr float insetX = 28, insetY = 18, marginX = 16, marginY = 6;
    pocket = {width - insetX + margin * marginX, height - insetY + margin * marginY, 1};
    const auto player = at<std::uintptr_t>(hud, layout::playerHud::player);
    const auto twin = at<std::uintptr_t>(player, layout::player::twin);
    // RenderPocketItems takes abs(scale), then flips text/item alignment for
    // nonprimary HUDs, except the younger twin. Cancel that flip for this full
    // right-side draw without changing HUD indices or player ownership.
    if (at<short>(hud, layout::playerHud::index) > 0 &&
        (!twin || at<int>(player, layout::player::index) <= at<int>(twin, layout::player::index) ||
         twin == player))
        pocket.scale = -1;
    return true;
}
} // namespace
const Bindings bindings{
    repentance::entry::craftingBagHudRender,
    repentance::entry::playerHudPocketRender,
    repentance::entry::playerGetActiveItem,
    repentance::globals::logicalWidth,
    repentance::globals::logicalHeight,
    {layout::playerHud::player, layout::playerHud::root, layout::playerHud::size},
    layout::player::controller,
    layout::player::coopGhost,
    PocketAbi::registerScaleAlpha,
    placePocket};
} // namespace isaac::engine::native_crafting_hud

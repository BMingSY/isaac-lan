#include "engine/versions/common/crafting_hud_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_crafting_hud {
namespace {
namespace layout = repentance_plus::layout;
bool placePocket(std::uintptr_t, std::uintptr_t, std::uintptr_t root, float width, float height,
                 PocketLayout& pocket) {
    constexpr float insetX = 28, insetY = 18;
    pocket = {width - insetX + *reinterpret_cast<const float*>(root + layout::hud::pocketOffsetX),
              height - insetY + *reinterpret_cast<const float*>(root + layout::hud::pocketOffsetY),
              1};
    return true;
}
} // namespace
const Bindings bindings{
    repentance_plus::entry::craftingBagHudRender,
    repentance_plus::entry::playerHudPocketRender,
    repentance_plus::entry::playerGetActiveItem,
    repentance_plus::globals::logicalWidth,
    repentance_plus::globals::logicalHeight,
    {layout::playerHud::player, layout::playerHud::root, layout::playerHud::size},
    layout::player::controller,
    layout::player::coopGhost,
    PocketAbi::stackLayoutAlpha,
    placePocket};
} // namespace isaac::engine::native_crafting_hud

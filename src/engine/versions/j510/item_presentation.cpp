#include "engine/versions/common/item_presentation_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_item_presentation {
namespace {
namespace backend = j510;
namespace layout = backend::layout;
using CustomText = void(__attribute__((thiscall)) *)(void*, void*, const char*, const char*);
void __attribute__((fastcall)) customText(void* hud, void*, void* actor, const char* title,
                                          const char* subtitle) {
    captureCustomText(hud, actor, title, subtitle, stickyText);
}
void callCustomText(void* original, void* hud, void* actor, const char* title, const char* subtitle,
                    unsigned) {
    reinterpret_cast<CustomText>(original)(hud, actor, title, subtitle);
}
bool indexedTextInRange(Address, const std::string&, int) {
    // This native version checks the category's ordered vector before reading.
    return true;
}
} // namespace
const Bindings bindings{
    {backend::entry::aNM2Construct,
     backend::entry::itemOverlayConfigConstruct,
     backend::entry::itemOverlayDestruct,
     backend::entry::itemOverlayLoad,
     backend::entry::itemOverlayUpdate,
     backend::entry::itemOverlayShow,
     backend::entry::itemOverlayRender,
     backend::entry::hUDShowItemText,
     backend::entry::hUDShowItemTextCustomUTF8,
     backend::entry::hudShowFortune,
     backend::entry::stringTableLookup,
     backend::entry::stringTableIndexed,
     backend::entry::gameAddPixelation,
     backend::entry::playerUpdateWavyCap,
     backend::entry::playerUsePill,
     backend::entry::playerUseCard,
     backend::entry::bossOverlayShow,
     backend::entry::managerGetItemConfig,
     backend::entry::itemConfigGetCollectible,
     backend::entry::itemConfigGetTrinket},
    backend::globals::game,
    backend::globals::manager,
    {{layout::game::stage, layout::game::stageType, layout::game::players,
      layout::game::itemOverlay, layout::game::bossOverlay, layout::game::hud,
      layout::game::pauseMenu, layout::game::pixelation, layout::game::pixelationDuration,
      layout::game::dizzyIntensity, layout::game::dizzyTarget, layout::game::dizzyStep,
      layout::game::bloomTime, layout::game::bloomDuration, layout::game::bloomIntensity},
     {layout::player::controller, layout::player::controlsEnabled},
     {layout::itemOverlay::size, layout::itemOverlay::state, layout::itemOverlay::id,
      layout::itemOverlay::book, layout::itemOverlay::configs, layout::itemOverlay::configCount,
      layout::itemOverlay::configStride, layout::itemOverlay::mega, layout::itemOverlay::delay},
     {layout::sprite::size, layout::sprite::animationOwner, layout::sprite::overlayOwner,
      layout::sprite::loaded, layout::sprite::playing, layout::sprite::frame},
     {layout::bossOverlay::state, layout::bossOverlay::id, layout::bossOverlay::sprite},
     {layout::manager::scene, layout::manager::stringTable, layout::manager::nightmare},
     {layout::nightmare::home, layout::nightmare::index, layout::nightmare::background,
      layout::nightmare::bubble},
     {layout::itemConfig::id, layout::itemConfig::type}},
    false,
    reinterpret_cast<void*>(customText),
    callCustomText,
    indexedTextInRange};
} // namespace isaac::engine::native_item_presentation

#include "engine/versions/common/item_presentation_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include <cstring>

namespace isaac::engine::native_item_presentation {
namespace {
namespace backend = j835;
namespace layout = backend::layout;
using CustomText = void(__attribute__((thiscall)) *)(void*, const char*, const char*, bool, bool);
void __attribute__((fastcall)) customText(void* hud, void*, const char* title, const char* subtitle,
                                          bool sticky, bool curse) {
    captureCustomText(hud, nullptr, title, subtitle,
                      (sticky ? stickyText : 0) | (curse ? curseText : 0));
}
void callCustomText(void* original, void* hud, void*, const char* title, const char* subtitle,
                    unsigned style) {
    reinterpret_cast<CustomText>(original)(hud, title, subtitle, style & stickyText,
                                           style & curseText);
}
template <class T> T at(Address address, unsigned offset) {
    return *reinterpret_cast<const T*>(address + offset);
}
bool indexedTextInRange(Address table, const std::string& category, int index) {
    // J835 advances an iterator without checking its end. Validate against
    // the live category map before passing a received fortune index to it.
    // Native category normalization folds ASCII capitals and path separators.
    if (!table || index < 0 || category.empty() || category.size() > 128 ||
        category.find('\0') != std::string::npos)
        return false;
    std::string normalized = category;
    for (auto& c : normalized) {
        if (c >= 'A' && c <= 'Z')
            c += 'a' - 'A';
        if (c == '\\')
            c = '/';
    }
    using namespace layout::stringTree;
    const auto categories = table + layout::stringTable::categories;
    const auto sentinel = at<Address>(categories, head);
    if (!sentinel)
        return false;
    auto node = at<Address>(sentinel, parent);
    // The native map is borrowed, never modified. Its own size bounds a
    // traversal even if a malformed local tree contains a cycle.
    for (auto remaining = at<unsigned>(categories, count);
         remaining && node && node != sentinel && !at<bool>(node, nil); --remaining) {
        const auto name = at<const char*>(node, key);
        if (!name)
            return false;
        const auto order = std::strcmp(normalized.c_str(), name);
        if (!order) {
            const auto strings = at<Address>(node, value);
            return strings && static_cast<unsigned>(index) < at<unsigned>(strings, count);
        }
        node = at<Address>(node, order < 0 ? left : right);
    }
    return false;
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
    true,
    reinterpret_cast<void*>(customText),
    callCustomText,
    indexedTextInRange};
} // namespace isaac::engine::native_item_presentation

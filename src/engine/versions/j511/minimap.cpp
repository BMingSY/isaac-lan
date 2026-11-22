#include "engine/versions/common/minimap_bindings.h"
#include "engine/versions/common/minimap.h"
#include <MinHook.h>
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
namespace isaac::engine::native_minimap {
namespace backend = j511;
namespace layout = backend::layout;
const Bindings bindings{backend::globals::game,
                        backend::globals::renderer,
                        {backend::entry::minimapUpdate, backend::entry::minimapRender,
                         backend::entry::minimapCache, backend::entry::renderingFlush},
                        {layout::game::minimap, layout::game::roomIndex, layout::game::dimension},
                        {layout::minimap::small, layout::minimap::large},
                        {layout::mapConfig::texture, layout::mapConfig::cellWidth,
                         layout::mapConfig::cellHeight, layout::mapConfig::cellSpacing,
                         layout::mapConfig::anchorX, layout::mapConfig::anchorY},
                        {layout::texture::width, layout::texture::height}};
namespace {
using TextureRender = void*(__attribute__((thiscall)) *)(void*, const void*, const void*, bool);
TextureRender originalTextureRender = nullptr;
void* __attribute__((fastcall)) textureRender(void* texture, void*, const void* quad,
                                              const void* destination, bool transparent) {
    observeTexture(reinterpret_cast<std::uintptr_t>(texture), static_cast<const float*>(quad),
                   static_cast<const unsigned char*>(quad)[layout::renderQuad::pixels] != 0,
                   static_cast<const float*>(destination),
                   static_cast<const float*>(destination)[11]);
    return originalTextureRender(texture, quad, destination, transparent);
}
} // namespace
bool ensureTextureHook(std::uintptr_t, std::uintptr_t texture) {
    if (originalTextureRender)
        return true;
    if (!texture)
        return false;
    const auto table = *reinterpret_cast<std::uintptr_t*>(texture);
    if (!table)
        return false;
    auto* target = *reinterpret_cast<void**>(table + layout::texture::renderVtableSlot);
    if (MH_CreateHook(target, reinterpret_cast<void*>(textureRender),
                      reinterpret_cast<void**>(&originalTextureRender)) != MH_OK)
        return false;
    if (MH_EnableHook(target) != MH_OK) {
        MH_RemoveHook(target);
        originalTextureRender = nullptr;
        return false;
    }
    return true;
}
} // namespace isaac::engine::native_minimap

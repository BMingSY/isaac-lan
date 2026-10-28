#include "engine/versions/common/minimap_bindings.h"
#include "engine/versions/common/minimap.h"
#include <MinHook.h>
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
namespace isaac::engine::native_minimap {
namespace backend = j835;
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
using TextureRender = void*(__attribute__((thiscall)) *)(void*, const float*, const float*,
                                                         const float*, const float*, const float*,
                                                         const float*);
TextureRender originalTextureRender = nullptr;
void* __attribute__((fastcall)) textureRender(void* texture, void*, const float* quad,
                                              const float* destination, const float* topLeft,
                                              const float* topRight, const float* bottomLeft,
                                              const float* bottomRight) {
    // J835 Draw accepts six stack arguments. DestinationQuad has only eight
    // coordinates; alpha belongs to a separate per-corner KAGE color.
    const bool normalized = *reinterpret_cast<const unsigned*>(
                                reinterpret_cast<const unsigned char*>(quad) +
                                layout::renderQuad::units) == layout::renderQuad::normalized;
    observeTexture(reinterpret_cast<std::uintptr_t>(texture), quad, !normalized, destination,
                   topLeft[3]);
    return originalTextureRender(texture, quad, destination, topLeft, topRight, bottomLeft,
                                 bottomRight);
}
} // namespace
bool ensureTextureHook(std::uintptr_t image, std::uintptr_t texture) {
    if (originalTextureRender)
        return true;
    if (!image || !texture)
        return false;
    auto* target = reinterpret_cast<void*>(image + backend::entry::textureRender);
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

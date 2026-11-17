#include "engine/player_opacity.h"
#include "engine/versions/common/player_opacity_bindings.h"
#include "engine/versions/common/branch_frame.h"
#include "engine/versions/common/hooks.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::presentation::player_opacity {
namespace backend = engine::j835;
namespace layout = backend::layout;
constinit const Layout layoutFields{layout::player::controller,
                                    {layout::entity::sprite, layout::player::syncSprites[0],
                                     layout::player::syncSprites[1],
                                     layout::player::syncSprites[2]},
                                    layout::player::costumesBegin,
                                    layout::player::costumesEnd,
                                    layout::costume::stride,
                                    4096};
namespace {
using Address = std::uintptr_t;
using Render = void(__attribute__((thiscall)) *)(void*, void*, void*, void*);
using RenderLayer = void(__attribute__((thiscall)) *)(void*, int, void*, void*, void*);
using Frame = engine::native_branch::Frame;
namespace registers = engine::native_branch;
Address image = 0;
bool installed = false;
Render originalRender = nullptr;
RenderLayer originalLayer = nullptr;
enum Pass : unsigned { sprite, beamSegments, beamCap, beamStraight, shadowSegments, shadowCap };
const std::array entries{
    backend::entry::spriteRenderColor,       backend::entry::laserSegmentColor,
    backend::entry::laserCapColor,           backend::entry::laserStraightColor,
    backend::entry::laserShadowSegmentColor, backend::entry::laserShadowCapColor};
std::array<void*, entries.size()> originals{};
constexpr unsigned tearType = 2, maximumSpawnerLinks = 128;
template <class T> T field(Address object, std::ptrdiff_t offset) {
    return *reinterpret_cast<const T*>(object + offset);
}
std::optional<float> projectileFactor(Address entity, bool tear) {
    if (!entity || !playersActive())
        return std::nullopt;
    auto owner = field<Address>(entity, layout::entity::spawner);
    if (tear)
        return playerFactor(owner);
    // Plus resolves a laser's final spawner before checking the local roster.
    // Original Repentance has no such render helper. EntityPtr keeps these
    // links live; bound traversal also rejects malformed/cyclic Mod chains.
    for (unsigned depth = 0; owner && depth < maximumSpawnerLinks; ++depth) {
        const auto next = field<Address>(owner, layout::entity::spawner);
        if (!next)
            return playerFactor(owner);
        owner = next;
    }
    return std::nullopt;
}
void __fastcall render(void* self, void*, void* position, void* topLeft, void* bottomRight) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    const auto sprite = reinterpret_cast<Address>(self);
    std::optional<float> factor;
    if (caller == backend::entry::entitySpriteRenderReturn) {
        const auto entity = sprite - layout::entity::sprite;
        if (field<unsigned>(entity, layout::entity::type) == tearType)
            factor = projectileFactor(entity, true);
    } else if (caller == backend::entry::laserSpriteRenderReturn) {
        factor = projectileFactor(sprite - layout::entity::sprite, false);
    }
    // Only the native draw call borrows a sprite factor. Mod render callbacks
    // run after this returns and observe the original entity/sprite colors.
    if (factor)
        withSprite(sprite, *factor, [&] { originalRender(self, position, topLeft, bottomRight); });
    else
        originalRender(self, position, topLeft, bottomRight);
}
void __fastcall renderLayer(void* self, void*, int layer, void* position, void* topLeft,
                            void* bottomRight) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    const auto sprite = reinterpret_cast<Address>(self);
    const auto factor = caller == backend::entry::laserLayerRenderReturn
                            ? projectileFactor(sprite - layout::entity::sprite, false)
                            : std::nullopt;
    if (factor)
        withSprite(sprite, *factor,
                   [&] { originalLayer(self, layer, position, topLeft, bottomRight); });
    else
        originalLayer(self, layer, position, topLeft, bottomRight);
}
} // namespace
extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_opacity_prepare(
    Frame* frame, unsigned pass) noexcept {
    (*frame)[registers::continuation] = reinterpret_cast<Address>(originals[pass]);
    const auto stack = (*frame)[registers::ebp];
    if (pass == sprite) {
        const auto source = field<Address>(stack, layout::spriteRenderFrame::sprite);
        if (const auto factor = spriteFactor(source))
            // All native shader paths copy the cached alpha into their draw
            // RGBA after this boundary. The full Color's alpha was already
            // cached and is no longer read for opacity here.
            *reinterpret_cast<float*>(stack + layout::spriteRenderFrame::alpha) *= *factor;
        return;
    }
    Address entity;
    if (pass == beamSegments)
        entity = field<Address>(stack, layout::laserRenderFrame::segmentEntity);
    else if (pass == shadowSegments)
        entity = field<Address>(stack, layout::laserRenderFrame::shadowEntity);
    else
        entity =
            (*frame)[pass == shadowCap ? registers::esi : registers::edi] - layout::entity::sprite;
    if (const auto factor = projectileFactor(entity, false)) {
        // At all five audited virtual draw calls the third argument points to
        // a fresh stack-local RGBA. Scale that copy once; no sprite, global
        // shadow color, UV, shader tint or renderer-owned buffer is modified.
        constexpr unsigned savedWords = 2, colorArgument = 2;
        const auto arguments = (*frame)[registers::esp] + savedWords * sizeof(Address);
        const auto color = field<Address>(arguments, colorArgument * sizeof(Address));
        *reinterpret_cast<float*>(color + layout::color::alpha) *= *factor;
    }
}
#define OPACITY_BOUNDARY(NAME, PASS)                                                               \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__(ISAAC_LAN_NATIVE_BRANCH_SAVE                                          \
                             "pushl $" #PASS "\n\tpushl %eax\n\t"                                  \
                             "call _isaac_lan_opacity_prepare\n\taddl $8, "                        \
                             "%esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE);                          \
    }
OPACITY_BOUNDARY(isaac_lan_opacity_color, 0)
OPACITY_BOUNDARY(isaac_lan_opacity_beam_segments, 1)
OPACITY_BOUNDARY(isaac_lan_opacity_beam_cap, 2)
OPACITY_BOUNDARY(isaac_lan_opacity_beam_straight, 3)
OPACITY_BOUNDARY(isaac_lan_opacity_shadow_segments, 4)
OPACITY_BOUNDARY(isaac_lan_opacity_shadow_cap, 5)
#undef OPACITY_BOUNDARY
}
bool install(Address base) {
    if (installed)
        return base == image;
    if (!base)
        return false;
    engine::native_hooks::Group<8> hooks;
    image = base;
    const auto failed = [&] {
        image = 0;
        originalRender = nullptr;
        originalLayer = nullptr;
        originals.fill(nullptr);
        return false;
    };
    const std::array detours{isaac_lan_opacity_color,           isaac_lan_opacity_beam_segments,
                             isaac_lan_opacity_beam_cap,        isaac_lan_opacity_beam_straight,
                             isaac_lan_opacity_shadow_segments, isaac_lan_opacity_shadow_cap};
    for (unsigned i = 0; i < entries.size(); ++i)
        if (!hooks.add(base + entries[i], detours[i], originals[i]))
            return failed();
    if (!hooks.add(base + backend::entry::spriteRender, render, originalRender) ||
        !hooks.add(base + backend::entry::spriteRenderLayer, renderLayer, originalLayer) ||
        !hooks.enable())
        return failed();
    installed = true;
    return true;
}
} // namespace isaac::presentation::player_opacity

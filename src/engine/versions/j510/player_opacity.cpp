#include "engine/player_opacity.h"
#include "engine/versions/common/player_opacity_bindings.h"
#include "engine/versions/common/branch_frame.h"
#include "engine/versions/common/hooks.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"
#include <array>

namespace isaac::presentation::player_opacity {
namespace j510 = engine::j510;
namespace layout = j510::layout;
constinit const Layout layoutFields{layout::player::controller,
                                    {layout::entity::sprite, layout::player::extraSprite,
                                     layout::player::ghostSprite, layout::player::auxiliarySprite},
                                    layout::player::costumes + layout::vector::begin,
                                    layout::player::costumes + layout::vector::end,
                                    layout::player::costumeStride,
                                    layout::player::maximumCostumes};
namespace {
using Address = std::uintptr_t;
bool installed = false;
Address image = 0;
enum Pass : unsigned { sprite, tear, laser, laserShadow };
struct Boundary {
    Address gate, draw;
    void* original = nullptr;
};
std::array<Boundary, 4> boundaries{{
    {j510::entry::spriteRenderColor, 0},
    {j510::entry::tearOpacityGate, j510::entry::tearOpacityDraw},
    {j510::entry::laserOpacityGate, j510::entry::laserOpacityDraw},
    {j510::entry::laserShadowOpacityGate, j510::entry::laserShadowOpacityDraw},
}};
} // namespace
extern "C" {
__attribute__((used,
               force_align_arg_pointer)) void __cdecl isaac_lan_opacity_prepare(Address* registers,
                                                                                unsigned pass) {
    // pushad: EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX, flags, continuation.
    enum Register : unsigned {
        entity = 1,
        frame = 2,
        tearOwner = 5,
        laserOwner = 7,
        continuation = 9
    };
    const auto& boundary = boundaries[pass];
    registers[continuation] = reinterpret_cast<Address>(boundary.original);
    if (pass != sprite) {
        // The native renderer has already resolved the owning player. Match
        // against this render's roster without retaining or dereferencing it.
        const auto factor = playerFactor(registers[pass == tear ? tearOwner : laserOwner]);
        if (!factor)
            return;
        if (pass == tear) {
            // Native Tear::Render saved this color before the online gate and
            // restores it after drawing, before MC_POST_TEAR_RENDER. Use that
            // same temporary modulation, retaining all tint/fade channels.
            auto& alpha = *reinterpret_cast<float*>(registers[entity] + layout::entity::sprite +
                                                    layout::sprite::color + layout::color::alpha);
            alpha *= *factor;
        } else {
            // Both laser passes consume a stack-local multiplier, including
            // native beam segments/rings that do not use Sprite::RenderColor.
            const auto offset = pass == laser ? layout::laserRenderFrame::opacity
                                              : layout::laserRenderFrame::shadowOpacity;
            *reinterpret_cast<float*>(registers[frame] + offset) = *factor;
        }
        registers[continuation] = image + boundary.draw;
        return;
    }
    const auto stack = registers[frame];
    const auto sprite =
        *reinterpret_cast<const Address*>(stack + layout::spriteRenderFrame::sprite);
    const auto factor = spriteFactor(sprite);
    if (!factor)
        return;
    auto& alpha =
        *reinterpret_cast<float*>(stack + layout::spriteRenderFrame::color + layout::color::alpha);
    alpha *= *factor;
}
#define OPACITY_BOUNDARY(NAME, PASS)                                                               \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__(ISAAC_LAN_NATIVE_BRANCH_SAVE                                          \
                             "pushl $" #PASS "\n\tpushl %eax\n\t"                                  \
                             "call _isaac_lan_opacity_prepare\n\taddl $8, "                        \
                             "%esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE);                          \
    }
OPACITY_BOUNDARY(isaac_lan_opacity_color, 0)
OPACITY_BOUNDARY(isaac_lan_opacity_tear, 1)
OPACITY_BOUNDARY(isaac_lan_opacity_laser, 2)
OPACITY_BOUNDARY(isaac_lan_opacity_laser_shadow, 3)
#undef OPACITY_BOUNDARY
}
bool install(Address base) {
    if (installed)
        return base == image;
    if (!base)
        return false;
    image = base;
    engine::native_hooks::Group<4> hooks;
    const std::array<void (*)(), 4> detours{isaac_lan_opacity_color, isaac_lan_opacity_tear,
                                            isaac_lan_opacity_laser,
                                            isaac_lan_opacity_laser_shadow};
    for (unsigned i = 0; i < boundaries.size(); ++i)
        if (!hooks.add(image + boundaries[i].gate, detours[i], boundaries[i].original)) {
            image = 0;
            return false;
        }
    if (!hooks.enable()) {
        image = 0;
        return false;
    }
    installed = true;
    return true;
}
} // namespace isaac::presentation::player_opacity

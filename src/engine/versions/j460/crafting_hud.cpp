#include "engine/crafting_hud.h"
#include "engine/versions/j460/entrypoints.h"
#include "runtime/session.h"
#include <MinHook.h>

namespace isaac::presentation {
extern "C" {
void* isaac_lan_crafting_hud_original = nullptr;
// PlayerHUD[0] is its borrowed player. No HUD binding, owned sprite, or gameplay
// material is modified. -2 hides while the replica has no committed view.
__attribute__((used, force_align_arg_pointer)) int __cdecl isaac_lan_crafting_hud_visible(
    std::uintptr_t hud) {
    const int target = runtime::craftingBagViewTarget();
    if (target == -1)
        return 1;
    if (target < 0 || !hud)
        return 0;
    const auto player = *reinterpret_cast<std::uintptr_t*>(hud);
    return player && *reinterpret_cast<int*>(player + 0x1618) == target + 1 &&
           !*reinterpret_cast<bool*>(player + 0x20a9);
}
// J460: ECX=PlayerHUD, [ESP+4]=Vector*, XMM2=scale, callee pops 4.
// Tail-call the trampoline with the complete original register state. The
// function contains BOTH the cached recipe preview and eight material icons.
__attribute__((naked)) void isaac_lan_crafting_hud_thunk() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tsubl $128, %esp\n\t"
                         "movups %xmm0, 0(%esp)\n\t"
                         "movups %xmm1, 16(%esp)\n\t"
                         "movups %xmm2, 32(%esp)\n\t"
                         "movups %xmm3, 48(%esp)\n\t"
                         "movups %xmm4, 64(%esp)\n\t"
                         "movups %xmm5, 80(%esp)\n\t"
                         "movups %xmm6, 96(%esp)\n\t"
                         "movups %xmm7, 112(%esp)\n\t"
                         "pushl %ecx\n\tcall _isaac_lan_crafting_hud_visible\n\t"
                         "addl $4, %esp\n\ttestl %eax, %eax\n\tjz 1f\n\t"
                         "movups 0(%esp), %xmm0\n\t"
                         "movups 16(%esp), %xmm1\n\t"
                         "movups 32(%esp), %xmm2\n\t"
                         "movups 48(%esp), %xmm3\n\t"
                         "movups 64(%esp), %xmm4\n\t"
                         "movups 80(%esp), %xmm5\n\t"
                         "movups 96(%esp), %xmm6\n\t"
                         "movups 112(%esp), %xmm7\n\t"
                         "addl $128, %esp\n\tpopal\n\tpopfl\n\t"
                         "jmp *_isaac_lan_crafting_hud_original\n\t1:\n\t"
                         "movups 0(%esp), %xmm0\n\t"
                         "movups 16(%esp), %xmm1\n\t"
                         "movups 32(%esp), %xmm2\n\t"
                         "movups 48(%esp), %xmm3\n\t"
                         "movups 64(%esp), %xmm4\n\t"
                         "movups 80(%esp), %xmm5\n\t"
                         "movups 96(%esp), %xmm6\n\t"
                         "movups 112(%esp), %xmm7\n\t"
                         "addl $128, %esp\n\tpopal\n\tpopfl\n\t"
                         "ret $4");
}
}
bool installCraftingHud(std::uintptr_t image) {
    const auto target = reinterpret_cast<void*>(image + engine::j460::entry::craftingBagHudRender);
    return MH_CreateHook(target, reinterpret_cast<void*>(isaac_lan_crafting_hud_thunk),
                         &isaac_lan_crafting_hud_original) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
} // namespace isaac::presentation

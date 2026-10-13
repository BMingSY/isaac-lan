#include "engine/crafting_hud.h"
#include "engine/versions/j460/entrypoints.h"
#include "runtime/session.h"
#include <MinHook.h>

namespace isaac::presentation {
namespace {
using Address = std::uintptr_t;
template <class T> const T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<const T*>(address + offset);
}
bool localHud(Address hud) {
    const int slot = runtime::localViewSlot();
    if (!hud || slot < 0 || slot >= 4)
        return false;
    const auto player = at<Address>(hud);
    return player && at<int>(player, 0x1618) == slot + 1;
}
} // namespace
extern "C" {
void* isaac_lan_crafting_hud_original = nullptr;
void* isaac_lan_crafting_pocket_original = nullptr;
void* isaac_lan_crafting_get_active_item = nullptr;
const float* isaac_lan_crafting_screen_width = nullptr;
const float* isaac_lan_crafting_screen_height = nullptr;
// PlayerHUD[0] borrows its player and PlayerHUD[1] borrows the shared HUD.
// Select a receiver for this draw only; never rebind HUDs or copy owned caches.
// -2 hides while the replica has no committed view.
__attribute__((used, force_align_arg_pointer))
Address __cdecl isaac_lan_crafting_hud_receiver(std::uintptr_t hud) {
    const int target = runtime::craftingBagViewTarget();
    if (target == -1)
        return hud;
    if (target < 0 || target >= 4 || !localHud(hud) || target == runtime::localViewSlot())
        return 0;
    const auto root = at<Address>(hud, 4);
    if (!root || !isaac_lan_crafting_get_active_item)
        return 0;
    using GetActiveItem = int(__attribute__((thiscall))*)(void*, int);
    const auto activeItem = reinterpret_cast<GetActiveItem>(isaac_lan_crafting_get_active_item);
    for (unsigned i = 0; i < 8; ++i) {
        const auto candidate = root + i * 0x6dc;
        const auto player = at<Address>(candidate);
        if (!player || at<int>(player, 0x1618) != target + 1)
            continue;
        if (at<bool>(player, 0x20a9))
            return 0;
        // The original caller checks the local actor's selected pocket item.
        // Check the borrowed actor too: a transformation can remove its bag
        // while the HUD still owns a previous recipe texture.
        for (int slot = 0; slot < 4; ++slot)
            if (activeItem(reinterpret_cast<void*>(player), slot) == 710)
                return candidate;
        return 0;
    }
    return 0;
}
// Return 1 for an unchanged native call, 2 for the full local pocket layout,
// and 0 for a hidden teammate or an unavailable local view.
__attribute__((used, force_align_arg_pointer)) int __cdecl isaac_lan_crafting_pocket_layout(
    std::uintptr_t hud, float* position) {
    const int target = runtime::craftingBagViewTarget();
    if (target == -1)
        return 1;
    if (target < 0 || target >= 4 || !localHud(hud))
        return 0;
    const auto root = at<Address>(hud, 4);
    if (!root || !isaac_lan_crafting_screen_width || !isaac_lan_crafting_screen_height)
        return 0;
    // Match HUD::Render's full-size pocket call at J460 RVA 0x5a73d0.
    // These native offsets already include the current HUDOffset and animation.
    position[0] = *isaac_lan_crafting_screen_width - 28.0f + at<float>(root, 0x594c);
    position[1] = *isaac_lan_crafting_screen_height - 18.0f + at<float>(root, 0x5950);
    return 2;
}

#define SAVE_HUD_REGISTERS                                                                         \
    "pushfl\n\tpushal\n\tsubl $128, %esp\n\t"                                                      \
    "movups %xmm0, 0(%esp)\n\tmovups %xmm1, 16(%esp)\n\t"                                          \
    "movups %xmm2, 32(%esp)\n\tmovups %xmm3, 48(%esp)\n\t"                                         \
    "movups %xmm4, 64(%esp)\n\tmovups %xmm5, 80(%esp)\n\t"                                         \
    "movups %xmm6, 96(%esp)\n\tmovups %xmm7, 112(%esp)\n\t"
#define RESTORE_HUD_REGISTERS                                                                      \
    "movups 0(%esp), %xmm0\n\tmovups 16(%esp), %xmm1\n\t"                                          \
    "movups 32(%esp), %xmm2\n\tmovups 48(%esp), %xmm3\n\t"                                         \
    "movups 64(%esp), %xmm4\n\tmovups 80(%esp), %xmm5\n\t"                                         \
    "movups 96(%esp), %xmm6\n\tmovups 112(%esp), %xmm7\n\t"                                        \
    "addl $128, %esp\n\tpopal\n\tpopfl\n\t"
// J460: ECX=PlayerHUD, [ESP+4]=Vector*, XMM2=scale, callee pops 4.
// Borrow only the next player's receiver; the local native position and scale
// place BOTH its cached recipe preview and materials in the local pocket HUD.
__attribute__((naked)) void isaac_lan_crafting_hud_thunk() {
    __asm__ __volatile__(SAVE_HUD_REGISTERS
                         "pushl %ecx\n\tcall _isaac_lan_crafting_hud_receiver\n\t"
                         "addl $4, %esp\n\ttestl %eax, %eax\n\tjz 1f\n\t"
                         "movl %eax, 152(%esp)\n\t" // Saved ECX in pushal frame.
                         RESTORE_HUD_REGISTERS
                         "jmp *_isaac_lan_crafting_hud_original\n\t1:\n\t" RESTORE_HUD_REGISTERS
                         "ret $4");
}
// J460: ECX=PlayerHUD, XMM3=scale; Vector*, layout and alpha occupy 12 stack
// bytes. Keep the local actor's cards, pills and active-item icon. Native 3/4
// player layouts move this whole region into a small HUD; draw the full native
// bottom-right layout instead, without changing the caller's Vector or HUD.
// The temporary Vector remains on our stack throughout the original call.
__attribute__((naked)) void isaac_lan_crafting_pocket_thunk() {
    __asm__ __volatile__(SAVE_HUD_REGISTERS "subl $16, %esp\n\tmovl %esp, %eax\n\t"
                                            "pushl %eax\n\tpushl %ecx\n\t"
                                            "call _isaac_lan_crafting_pocket_layout\n\t"
                                            "addl $8, %esp\n\ttestl %eax, %eax\n\tjz 1f\n\t"
                                            "cmpl $1, %eax\n\tje 2f\n\t"
                                            // ESP now points to a private Vector and saved XMM3.
                                            // Copy alpha, full-layout mode and Vector* as new args.
                                            "movl 64(%esp), %eax\n\tmovl %eax, 8(%esp)\n\t"
                                            "movl $0x3f800000, 64(%esp)\n\t"
                                            "movl %esp, %eax\n\tpushl 192(%esp)\n\t"
                                            "pushl $0\n\tpushl %eax\n\t"
                                            // Reload the original register file for the native
                                            // draw, changing only XMM3's low float to scale 1.
                                            "movups 28(%esp), %xmm0\n\tmovups 44(%esp), %xmm1\n\t"
                                            "movups 60(%esp), %xmm2\n\tmovups 76(%esp), %xmm3\n\t"
                                            "movups 92(%esp), %xmm4\n\tmovups 108(%esp), %xmm5\n\t"
                                            "movups 124(%esp), %xmm6\n\tmovups 140(%esp), %xmm7\n\t"
                                            "movl 156(%esp), %edi\n\tmovl 160(%esp), %esi\n\t"
                                            "movl 164(%esp), %ebp\n\tmovl 172(%esp), %ebx\n\t"
                                            "movl 176(%esp), %edx\n\tmovl 180(%esp), %ecx\n\t"
                                            "movl 184(%esp), %eax\n\tpushl 188(%esp)\n\tpopfl\n\t"
                                            "call *_isaac_lan_crafting_pocket_original\n\t"
                                            // The original callee consumed the three copied args.
                                            "movl 8(%esp), %eax\n\tmovl %eax, 64(%esp)\n\t"
                                            "1:\n\taddl $16, %esp\n\t" RESTORE_HUD_REGISTERS
                                            "ret $12\n\t"
                                            "2:\n\taddl $16, %esp\n\t" RESTORE_HUD_REGISTERS
                                            "jmp *_isaac_lan_crafting_pocket_original");
}
#undef SAVE_HUD_REGISTERS
#undef RESTORE_HUD_REGISTERS
}
bool installCraftingHud(std::uintptr_t image) {
    const auto target = reinterpret_cast<void*>(image + engine::j460::entry::craftingBagHudRender);
    const auto pocket = reinterpret_cast<void*>(image + engine::j460::entry::playerHudPocketRender);
    isaac_lan_crafting_get_active_item =
        reinterpret_cast<void*>(image + engine::j460::entry::playerGetActiveItem);
    isaac_lan_crafting_screen_width =
        reinterpret_cast<const float*>(image + engine::j460::globals::logicalWidth);
    isaac_lan_crafting_screen_height =
        reinterpret_cast<const float*>(image + engine::j460::globals::logicalHeight);
    return MH_CreateHook(pocket, reinterpret_cast<void*>(isaac_lan_crafting_pocket_thunk),
                         &isaac_lan_crafting_pocket_original) == MH_OK &&
           MH_CreateHook(target, reinterpret_cast<void*>(isaac_lan_crafting_hud_thunk),
                         &isaac_lan_crafting_hud_original) == MH_OK &&
           MH_EnableHook(pocket) == MH_OK && MH_EnableHook(target) == MH_OK;
}
} // namespace isaac::presentation

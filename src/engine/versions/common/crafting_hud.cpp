#include "engine/versions/common/player_seats.h"
#include "engine/crafting_hud.h"
#include "engine/rooms.h"
#include "compat/game_ids.h"
#include "engine/versions/common/crafting_hud_bindings.h"
#include "engine/versions/common/player_hud.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <array>

namespace isaac::presentation {
namespace {
using Address = std::uintptr_t;
using engine::native_crafting_hud::bindings;
using engine::native_crafting_hud::PocketLayout;
namespace panels = engine::native_player_hud;
Address image;
bool installed;
template <class T> const T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<const T*>(address + offset);
}
bool localHud(Address hud) {
    const int slot = runtime::localViewSlot();
    if (!hud || !panels::seatBit(slot))
        return false;
    const auto player = at<Address>(hud, bindings.playerHud.player);
    return player && isaac::engine::player_seats::owner(
                         player, at<int>(player, bindings.controller)) == slot + 1;
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
    const auto connected = rooms::connected();
    if (!(connected & panels::seatBit(target)) || panels::localOnly(connected) || !localHud(hud) ||
        target == runtime::localViewSlot())
        return 0;
    const auto root = at<Address>(hud, bindings.playerHud.root);
    if (!root || !isaac_lan_crafting_get_active_item)
        return 0;
    using GetActiveItem = int(__attribute__((thiscall))*)(void*, int);
    const auto activeItem = reinterpret_cast<GetActiveItem>(isaac_lan_crafting_get_active_item);
    for (unsigned i = 0; i < panels::totalPanels; ++i) {
        const auto candidate = root + i * bindings.playerHud.stride;
        const auto player = at<Address>(candidate, bindings.playerHud.player);
        if (!player || isaac::engine::player_seats::owner(
                           player, at<int>(player, bindings.controller)) != target + 1)
            continue;
        if (at<bool>(player, bindings.coopGhost))
            return 0;
        // The original caller checks the local actor's selected pocket item.
        // Check the borrowed actor too: a transformation can remove its bag
        // while the HUD still owns a previous recipe texture.
        for (int slot = 0; slot < 4; ++slot)
            if (activeItem(reinterpret_cast<void*>(player), slot) ==
                compat::ids::collectible::bagOfCrafting)
                return candidate;
        return 0;
    }
    return 0;
}
// Return 1 for an unchanged native call, 2 for the full local pocket layout,
// and 0 for a hidden teammate or an unavailable local view.
__attribute__((used, force_align_arg_pointer)) int __cdecl isaac_lan_crafting_pocket_layout(
    std::uintptr_t hud, PocketLayout* layout) {
    const int target = runtime::craftingBagViewTarget();
    if (target == -1)
        return 1;
    // Keep the local pocket when the challenge's next seat is offline.
    if (!panels::seatBit(target) || !localHud(hud))
        return 0;
    const auto root = at<Address>(hud, bindings.playerHud.root);
    if (!root || !isaac_lan_crafting_screen_width || !isaac_lan_crafting_screen_height)
        return 0;
    return bindings.placePocket(image, hud, root, *isaac_lan_crafting_screen_width,
                                *isaac_lan_crafting_screen_height, *layout)
               ? 2
               : 0;
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
// Both versions: ECX=PlayerHUD, [ESP+4]=Vector*, XMM2=scale, callee pops 4.
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
// Repentance+: ECX=PlayerHUD, XMM3=scale; Vector*, layout and alpha occupy 12 stack
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
// Repentance: ECX=PlayerHUD, XMM2=signed scale, XMM3=alpha, one Vector*
// stack argument, ret 4. The sign cancels native HUD-index mirroring when the
// local pocket is placed at the full bottom-right anchor. Keep alpha intact.
__attribute__((naked)) void isaac_lan_crafting_pocket_registers_thunk() {
    __asm__ __volatile__(SAVE_HUD_REGISTERS "subl $16, %esp\n\tmovl %esp, %eax\n\t"
                                            "pushl %eax\n\tpushl %ecx\n\t"
                                            "call _isaac_lan_crafting_pocket_layout\n\t"
                                            "addl $8, %esp\n\ttestl %eax, %eax\n\tjz 1f\n\t"
                                            "cmpl $1, %eax\n\tje 2f\n\t"
                                            // Private x/y/scale occupy 12 bytes; save the original
                                            // low XMM2 word in the remaining four bytes.
                                            "movl 48(%esp), %eax\n\tmovl %eax, 12(%esp)\n\t"
                                            "movl 8(%esp), %eax\n\tmovl %eax, 48(%esp)\n\t"
                                            "movl %esp, %eax\n\tpushl %eax\n\t"
                                            "movups 20(%esp), %xmm0\n\tmovups 36(%esp), %xmm1\n\t"
                                            "movups 52(%esp), %xmm2\n\tmovups 68(%esp), %xmm3\n\t"
                                            "movups 84(%esp), %xmm4\n\tmovups 100(%esp), %xmm5\n\t"
                                            "movups 116(%esp), %xmm6\n\tmovups 132(%esp), %xmm7\n\t"
                                            "movl 148(%esp), %edi\n\tmovl 152(%esp), %esi\n\t"
                                            "movl 156(%esp), %ebp\n\tmovl 164(%esp), %ebx\n\t"
                                            "movl 168(%esp), %edx\n\tmovl 172(%esp), %ecx\n\t"
                                            "movl 176(%esp), %eax\n\tpushl 180(%esp)\n\tpopfl\n\t"
                                            "call *_isaac_lan_crafting_pocket_original\n\t"
                                            "movl 12(%esp), %eax\n\tmovl %eax, 48(%esp)\n\t"
                                            "1:\n\taddl $16, %esp\n\t" RESTORE_HUD_REGISTERS
                                            "ret $4\n\t"
                                            "2:\n\taddl $16, %esp\n\t" RESTORE_HUD_REGISTERS
                                            "jmp *_isaac_lan_crafting_pocket_original");
}
#undef SAVE_HUD_REGISTERS
#undef RESTORE_HUD_REGISTERS
}
bool installCraftingHud(std::uintptr_t base) {
    if (!base || installed)
        return false;
    image = base;
    isaac_lan_crafting_get_active_item = reinterpret_cast<void*>(base + bindings.activeItem);
    isaac_lan_crafting_screen_width = reinterpret_cast<const float*>(base + bindings.width);
    isaac_lan_crafting_screen_height = reinterpret_cast<const float*>(base + bindings.height);
    std::array<void*, 2> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned rva, auto detour, void*& original) {
        auto* target = reinterpret_cast<void*>(base + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(detour), &original) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    const auto pocket =
        bindings.pocketAbi == engine::native_crafting_hud::PocketAbi::stackLayoutAlpha
            ? isaac_lan_crafting_pocket_thunk
            : isaac_lan_crafting_pocket_registers_thunk;
    bool success =
        hook(bindings.pocket, pocket, isaac_lan_crafting_pocket_original) &&
        hook(bindings.bag, isaac_lan_crafting_hud_thunk, isaac_lan_crafting_hud_original);
    if (success) {
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
        if (success)
            success = MH_ApplyQueued() == MH_OK;
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        image = 0;
        isaac_lan_crafting_hud_original = isaac_lan_crafting_pocket_original = nullptr;
        isaac_lan_crafting_get_active_item = nullptr;
        isaac_lan_crafting_screen_width = isaac_lan_crafting_screen_height = nullptr;
    }
    installed = success;
    return success;
}
} // namespace isaac::presentation

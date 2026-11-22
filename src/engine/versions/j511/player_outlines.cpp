#include "engine/player_outlines.h"
#include "engine/versions/common/player_outlines.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
#include "presentation/player_outlines.h"
#include <MinHook.h>
#include <array>

namespace isaac::presentation::outlines {
namespace {
namespace j511 = engine::j511;
static_assert(sizeof(Color) == j511::layout::color::size);
using Address = std::uintptr_t;
Address image = 0;
struct Boundary {
    unsigned gate, draw, colorReturn;
    bool checksHologram;
    void* original = nullptr;
};
std::array<Boundary, 3> boundaries{{
    {j511::entry::playerOutlineBodyGate, j511::entry::playerOutlineBodyDraw,
     j511::entry::playerOutlineBodyColorReturn, true},
    {j511::entry::playerOutlineSpecialGate, j511::entry::playerOutlineSpecialDraw,
     j511::entry::playerOutlineSpecialColorReturn, true},
    {j511::entry::playerOutlineGhostGate, j511::entry::playerOutlineGhostDraw,
     j511::entry::playerOutlineGhostColorReturn, false},
}};
template <class T> T read(Address address, std::ptrdiff_t offset) {
    return *reinterpret_cast<const T*>(address + offset);
}
std::optional<unsigned> slot(Address player) {
    if (!participants || !player)
        return {};
    const auto controller = read<int>(player, j511::layout::player::controller);
    return controllerSlot(controller);
}
using PlayerColor = Color*(__attribute__((thiscall)) *)(void*, Color*, void*);
PlayerColor originalColor = nullptr;
Color* colorForCaller(void* manager, Color* result, void* player, Address caller) {
    const auto owner = slot(reinterpret_cast<Address>(player));
    bool outline = false;
    for (const auto& boundary : boundaries)
        outline |= caller == image + boundary.colorReturn;
    if (!owner || !outline)
        return originalColor(manager, result, player);
    // Native ColorMod: RGBA multiplier, four colorize values, RGB offset.
    *result = nativeColor(*owner);
    return result;
}
Color* __attribute__((fastcall)) playerColor(void* manager, void*, Color* result, void* player) {
    return colorForCaller(manager, result, player,
                          reinterpret_cast<Address>(__builtin_return_address(0)));
}
} // namespace
extern "C" {
__attribute__((used,
               force_align_arg_pointer)) void __cdecl isaac_lan_outline_prepare(Address* registers,
                                                                                unsigned index) {
    const auto& boundary = boundaries[index];
    // pushad saves EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX, then flags and
    // our reserved continuation. All three native outline gates own EBX=player.
    enum Register : unsigned { frame = 2, player = 4, continuation = 9 };
    registers[continuation] = reinterpret_cast<Address>(boundary.original);
    if (!slot(registers[player]) ||
        !read<bool>(registers[frame], j511::layout::playerRenderFrame::mainPass) ||
        (boundary.checksHologram &&
         read<bool>(registers[frame], j511::layout::playerRenderFrame::hologram)))
        return;
    // Skip only the Steam-lobby eligibility check. The existing native outline
    // pass retains body/head/costume ordering, offsets and color-stack cleanup.
    registers[continuation] = image + boundary.draw;
}
#define OUTLINE_BOUNDARY(NAME, INDEX)                                                              \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__("pushl $0\n\tpushfl\n\tpushal\n\tsubl $128, %esp\n\t"                 \
                             "movups %xmm0, 0(%esp)\n\tmovups %xmm1, 16(%esp)\n\t"                 \
                             "movups %xmm2, 32(%esp)\n\tmovups %xmm3, 48(%esp)\n\t"                \
                             "movups %xmm4, 64(%esp)\n\tmovups %xmm5, 80(%esp)\n\t"                \
                             "movups %xmm6, 96(%esp)\n\tmovups %xmm7, 112(%esp)\n\t"               \
                             "leal 128(%esp), %eax\n\tpushl $" #INDEX "\n\tpushl %eax\n\t"         \
                             "call _isaac_lan_outline_prepare\n\taddl $8, %esp\n\t"                \
                             "movups 0(%esp), %xmm0\n\tmovups 16(%esp), %xmm1\n\t"                 \
                             "movups 32(%esp), %xmm2\n\tmovups 48(%esp), %xmm3\n\t"                \
                             "movups 64(%esp), %xmm4\n\tmovups 80(%esp), %xmm5\n\t"                \
                             "movups 96(%esp), %xmm6\n\tmovups 112(%esp), %xmm7\n\t"               \
                             "addl $128, %esp\n\tpopal\n\tpopfl\n\tret");                          \
    }
OUTLINE_BOUNDARY(isaac_lan_outline_body, 0)
OUTLINE_BOUNDARY(isaac_lan_outline_special, 1)
OUTLINE_BOUNDARY(isaac_lan_outline_ghost, 2)
#undef OUTLINE_BOUNDARY
}
bool install(Address base) {
    image = base;
    const std::array<void (*)(), 3> detours{isaac_lan_outline_body, isaac_lan_outline_special,
                                            isaac_lan_outline_ghost};
    // Create the complete set before enabling any gate.
    for (unsigned i = 0; i < boundaries.size(); ++i) {
        auto& boundary = boundaries[i];
        if (MH_CreateHook(reinterpret_cast<void*>(image + boundary.gate),
                          reinterpret_cast<void*>(detours[i]), &boundary.original) != MH_OK)
            return false;
    }
    const auto color = reinterpret_cast<void*>(image + j511::entry::playerOutlineColor);
    if (MH_CreateHook(color, reinterpret_cast<void*>(playerColor),
                      reinterpret_cast<void**>(&originalColor)) != MH_OK ||
        MH_EnableHook(color) != MH_OK)
        return false;
    for (const auto& boundary : boundaries)
        if (MH_EnableHook(reinterpret_cast<void*>(image + boundary.gate)) != MH_OK)
            return false;
    return true;
}
} // namespace isaac::presentation::outlines

// Execute both production x86 HUD detours without loading the game.
#include "test_support.h"
#include <array>
#include <bit>
#include <cstdint>
#include <cstdio>
namespace isaac::runtime {
int target = -1, local = -1;
int craftingBagViewTarget() {
    return target;
}
int localViewSlot() {
    return local;
}
} // namespace isaac::runtime
extern "C" {
extern void* isaac_lan_crafting_hud_original;
extern void* isaac_lan_crafting_pocket_original;
extern void* isaac_lan_crafting_get_active_item;
extern const float* isaac_lan_crafting_screen_width;
extern const float* isaac_lan_crafting_screen_height;
void isaac_lan_crafting_hud_thunk();
void isaac_lan_crafting_pocket_thunk();
unsigned hudCalls = 0, activeItemCalls = 0;
std::uintptr_t observedHud = 0, observedPosition = 0, invocationHud = 0, invocationPosition = 0;
int observedLayout = 0, invocationLayout = 0;
std::uint32_t observedAlpha = 0, invocationAlpha = 0, observedFlags = 0, returnedFlags = 0;
std::uintptr_t returnedHud = 0, invocationStack = 0, returnedStack = 0;
std::uintptr_t returnedPositionArgument = 0;
std::uint32_t returnedLayoutArgument = 0, returnedAlphaArgument = 0, savedReturnEax = 0;
std::array<std::uint32_t, 32> invocationXmm{}, observedXmm{}, returnedXmm{};
std::array<std::uint32_t, 6> observedGpr{}, returnedGpr{};
std::array<float, 2> observedPositionValue{};
int __attribute__((thiscall)) activeItemFixture(void* player, int slot) {
    ++activeItemCalls;
    return *reinterpret_cast<int*>(static_cast<std::uint8_t*>(player) + 0x1580 + 0x20 * slot);
}
#define RECORD_REGISTERS                                                                           \
    "pushfl\n\tpopl _observedFlags\n\t"                                                            \
    "movl %eax, _observedGpr\n\tmovl %edx, _observedGpr+4\n\t"                                     \
    "movl %ebx, _observedGpr+8\n\tmovl %ebp, _observedGpr+12\n\t"                                  \
    "movl %esi, _observedGpr+16\n\tmovl %edi, _observedGpr+20\n\t"                                 \
    "incl _hudCalls\n\tmovl %ecx, _observedHud\n\t"                                                \
    "movl 4(%esp), %eax\n\tmovl %eax, _observedPosition\n\t"                                       \
    "movl (%eax), %edx\n\tmovl %edx, _observedPositionValue\n\t"                                   \
    "movl 4(%eax), %edx\n\tmovl %edx, _observedPositionValue+4\n\t"                                \
    "movups %xmm0, _observedXmm\n\tmovups %xmm1, _observedXmm+16\n\t"                              \
    "movups %xmm2, _observedXmm+32\n\tmovups %xmm3, _observedXmm+48\n\t"                           \
    "movups %xmm4, _observedXmm+64\n\tmovups %xmm5, _observedXmm+80\n\t"                           \
    "movups %xmm6, _observedXmm+96\n\tmovups %xmm7, _observedXmm+112\n\t"
__attribute__((naked)) void originalBagFixture() {
    __asm__ __volatile__(RECORD_REGISTERS "ret $4");
}
__attribute__((naked)) void originalPocketFixture() {
    __asm__ __volatile__(RECORD_REGISTERS
                         "movl 8(%esp), %eax\n\tmovl %eax, _observedLayout\n\t"
                         "movl 12(%esp), %eax\n\tmovl %eax, _observedAlpha\n\tret $12");
}
#undef RECORD_REGISTERS
#define LOAD_REGISTERS                                                                             \
    "movups _invocationXmm, %xmm0\n\t"                                                             \
    "movups _invocationXmm+16, %xmm1\n\tmovups _invocationXmm+32, %xmm2\n\t"                       \
    "movups _invocationXmm+48, %xmm3\n\tmovups _invocationXmm+64, %xmm4\n\t"                       \
    "movups _invocationXmm+80, %xmm5\n\tmovups _invocationXmm+96, %xmm6\n\t"                       \
    "movups _invocationXmm+112, %xmm7\n\t"                                                         \
    "xorl %eax, %eax\n\tmovl $0x1234, %eax\n\tmovl $0x2345, %edx\n\t"                              \
    "movl $0x3456, %ebx\n\tmovl $0x4567, %ebp\n\t"                                                 \
    "movl $0x5678, %esi\n\tmovl $0x6789, %edi\n\tmovl _invocationHud, %ecx\n\t"
#define RECORD_RETURNED                                                                            \
    "pushfl\n\tpopl _returnedFlags\n\tmovl %ecx, _returnedHud\n\t"                                 \
    "movl %eax, _returnedGpr\n\tmovl %edx, _returnedGpr+4\n\t"                                     \
    "movl %ebx, _returnedGpr+8\n\tmovl %ebp, _returnedGpr+12\n\t"                                  \
    "movl %esi, _returnedGpr+16\n\tmovl %edi, _returnedGpr+20\n\t"                                 \
    "movups %xmm0, _returnedXmm\n\tmovups %xmm1, _returnedXmm+16\n\t"                              \
    "movups %xmm2, _returnedXmm+32\n\tmovups %xmm3, _returnedXmm+48\n\t"                           \
    "movups %xmm4, _returnedXmm+64\n\tmovups %xmm5, _returnedXmm+80\n\t"                           \
    "movups %xmm6, _returnedXmm+96\n\tmovups %xmm7, _returnedXmm+112\n\t"
__attribute__((naked)) void invokeBagFixture() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, _invocationStack\n\t" LOAD_REGISTERS
                         "pushl _invocationPosition\n\tcall _isaac_lan_crafting_hud_thunk\n\t"
                         "movl %esp, _returnedStack\n\tmovl %eax, _savedReturnEax\n\t"
                         "movl -4(%esp), %eax\n\tmovl %eax, _returnedPositionArgument\n\t"
                         "movl _savedReturnEax, %eax\n\t" RECORD_RETURNED "popal\n\tpopfl\n\tret");
}
__attribute__((naked)) void invokePocketFixture() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, _invocationStack\n\t" LOAD_REGISTERS
                         "pushl _invocationAlpha\n\tpushl _invocationLayout\n\t"
                         "pushl _invocationPosition\n\tcall _isaac_lan_crafting_pocket_thunk\n\t"
                         "movl %esp, _returnedStack\n\tmovl %eax, _savedReturnEax\n\t"
                         "movl -12(%esp), %eax\n\tmovl %eax, _returnedPositionArgument\n\t"
                         "movl -8(%esp), %eax\n\tmovl %eax, _returnedLayoutArgument\n\t"
                         "movl -4(%esp), %eax\n\tmovl %eax, _returnedAlphaArgument\n\t"
                         "movl _savedReturnEax, %eax\n\t" RECORD_RETURNED "popal\n\tpopfl\n\tret");
}
#undef LOAD_REGISTERS
#undef RECORD_RETURNED
}
float screenWidth = 640, screenHeight = 360;
std::array<float, 2> expectedAnchor{612, 342};
void invoke(bool pocket, std::uintptr_t hud, std::uintptr_t expected, int layout, float scale) {
    std::array<float, 2> position{12 + layout * 21.0f, 34 - layout * 7.0f};
    const auto originalPosition = position;
    invocationHud = hud;
    invocationPosition = reinterpret_cast<std::uintptr_t>(&position);
    invocationLayout = layout;
    invocationAlpha = std::bit_cast<std::uint32_t>(layout ? 0.35f : 1.0f);
    for (unsigned i = 0; i < invocationXmm.size(); ++i)
        invocationXmm[i] = 0x3e800001u + i;
    invocationXmm[pocket ? 12 : 8] = std::bit_cast<std::uint32_t>(scale);
    observedXmm.fill(0);
    observedGpr.fill(0);
    hudCalls = 0;
    (pocket ? invokePocketFixture : invokeBagFixture)();
    require(hudCalls == unsigned(expected != 0), "HUD draw count changed");
    require(position == originalPosition, "HUD mutated the caller-owned position vector");
    require(returnedStack == invocationStack, "HUD unbalanced the caller stack");
    require(returnedPositionArgument == invocationPosition,
            "HUD changed the original position argument");
    if (pocket)
        require(returnedLayoutArgument == std::uint32_t(layout) &&
                    returnedAlphaArgument == invocationAlpha,
                "HUD changed the original layout/alpha argument slots");
    const std::array<std::uint32_t, 6> expectedGpr{0x1234, 0x2345, 0x3456, 0x4567, 0x5678, 0x6789};
    if (expected) {
        require(observedHud == expected, "HUD used the wrong borrowed receiver");
        auto expectedXmm = invocationXmm;
        if (pocket && isaac::runtime::target != -1) {
            require(observedPosition != reinterpret_cast<std::uintptr_t>(&position) &&
                        observedPositionValue == expectedAnchor,
                    "Local pocket did not use a separate native bottom-right anchor");
            require(observedLayout == 0, "Local pocket kept a compact co-op layout");
            expectedXmm[12] = std::bit_cast<std::uint32_t>(1.0f);
        } else {
            require(observedPosition == reinterpret_cast<std::uintptr_t>(&position) &&
                        observedPositionValue == originalPosition,
                    "Ordinary pocket or inner bag changed the caller's position");
            if (pocket)
                require(observedLayout == layout, "Ordinary pocket changed its layout");
        }
        if (pocket)
            require(observedAlpha == invocationAlpha, "Pocket HUD changed alpha");
        require(observedXmm == expectedXmm, "HUD changed SSE state or required scale");
        require(observedGpr == expectedGpr, "HUD changed a non-receiver general register");
        require((observedFlags & 0x8c5) == 0x44, "HUD changed arithmetic flags");
    } else {
        require(returnedHud == hud && returnedGpr == expectedGpr,
                "Hidden HUD changed receiver or general registers");
        require(returnedXmm == invocationXmm, "Hidden HUD changed SSE state");
        require((returnedFlags & 0x8c5) == 0x44, "Hidden HUD changed arithmetic flags");
    }
}
int main() {
    try {
        isaac_lan_crafting_hud_original = reinterpret_cast<void*>(originalBagFixture);
        isaac_lan_crafting_pocket_original = reinterpret_cast<void*>(originalPocketFixture);
        isaac_lan_crafting_get_active_item = reinterpret_cast<void*>(activeItemFixture);
        isaac_lan_crafting_screen_width = &screenWidth;
        isaac_lan_crafting_screen_height = &screenHeight;
        constexpr unsigned hudSize = 0x6dc, hudCount = 8;
        alignas(16) std::array<std::array<std::uint8_t, 0x2200>, 4> players{};
        alignas(16) std::array<std::uint8_t, 0x5954> root{};
        const auto rootAddress = reinterpret_cast<std::uintptr_t>(root.data());
        const auto hudAt = [&](unsigned index) { return rootAddress + index * hudSize; };
        const auto item = [&](unsigned player, unsigned slot, int value) {
            *reinterpret_cast<int*>(players[player].data() + 0x1580 + 0x20 * slot) = value;
        };
        // Native HUD record order is independent of LAN slot order.
        const std::array<unsigned, 4> order{2, 0, 3, 1};
        std::array<std::uintptr_t, 4> hudFor{};
        for (unsigned i = 0; i < hudCount; ++i) {
            auto* hud = reinterpret_cast<std::uintptr_t*>(root.data() + i * hudSize);
            hud[1] = rootAddress;
            if (i < players.size()) {
                const auto slot = order[i];
                hud[0] = reinterpret_cast<std::uintptr_t>(players[slot].data());
                *reinterpret_cast<int*>(players[slot].data() + 0x1618) = slot + 1;
                item(slot, 0, 710);
                hudFor[slot] = hudAt(i);
            }
        }
        const auto verify = [&](std::uintptr_t source, std::uintptr_t expectedBag,
                                std::uintptr_t expectedPocket) {
            const auto beforePlayers = players;
            const auto beforeRoot = root;
            for (int layout : {0, 1, 3})
                for (float scale : {0.5f, 1.0f}) {
                    invoke(false, source, expectedBag, layout, scale);
                    invoke(true, source, expectedPocket, layout, scale);
                }
            require(players == beforePlayers && root == beforeRoot,
                    "Rendering mutated player state or HUD ownership");
        };
        isaac::runtime::target = -1;
        for (int local : {-1, 0, 1, 2, 3}) {
            isaac::runtime::local = local;
            for (auto hud : hudFor)
                verify(hud, hud, hud);
        }
        isaac_lan_crafting_screen_width = nullptr;
        isaac_lan_crafting_screen_height = nullptr;
        verify(hudFor[0], hudFor[0], hudFor[0]);
        isaac_lan_crafting_screen_width = &screenWidth;
        isaac_lan_crafting_screen_height = &screenHeight;
        require(activeItemCalls == 0, "Ordinary HUD consulted challenge bag availability");
        for (unsigned count = 2; count <= 4; ++count)
            for (unsigned local = 0; local < count; ++local) {
                const auto next = (local + 1) % count;
                isaac::runtime::local = local;
                isaac::runtime::target = next;
                // Explicit expected anchors cover both logical resolutions,
                // HUD offset endpoints, and incoming compact layouts/scales.
                for (const std::array<float, 6> geometry : {
                         std::array<float, 6>{480, 270, 0, 0, 452, 252},
                         {480, 270, 10, 10, 462, 262},
                         {640, 360, 0, 0, 612, 342},
                         {640, 360, 10, 10, 622, 352},
                         {640, 360, -10, -10, 602, 332},
                     }) {
                    screenWidth = geometry[0];
                    screenHeight = geometry[1];
                    *reinterpret_cast<float*>(root.data() + 0x594c) = geometry[2];
                    *reinterpret_cast<float*>(root.data() + 0x5950) = geometry[3];
                    expectedAnchor = {geometry[4], geometry[5]};
                    for (unsigned source = 0; source < count; ++source)
                        verify(hudFor[source], source == local ? hudFor[next] : 0,
                               source == local ? hudFor[local] : 0);
                }
                // Local ghost keeps its fixed next seat. Target ghost hides
                // only the bag, retaining local cards, pills and pocket icons.
                players[local][0x20a9] = 1;
                verify(hudFor[local], hudFor[next], hudFor[local]);
                players[local][0x20a9] = 0;
                players[next][0x20a9] = 1;
                verify(hudFor[local], 0, hudFor[local]);
                players[next][0x20a9] = 0;
                item(next, 0, 0);
                verify(hudFor[local], 0, hudFor[local]);
                for (unsigned slot = 0; slot < 4; ++slot) {
                    item(next, slot, 710);
                    verify(hudFor[local], hudFor[next], hudFor[local]);
                    item(next, slot, 0);
                }
                item(next, 0, 710);
                auto* targetHud = reinterpret_cast<std::uintptr_t*>(hudFor[next]);
                const auto targetPlayer = targetHud[0];
                targetHud[0] = 0;
                verify(hudFor[local], 0, hudFor[local]);
                targetHud[0] = targetPlayer;
                auto* sourceHud = reinterpret_cast<std::uintptr_t*>(hudFor[local]);
                sourceHud[1] = 0;
                verify(hudFor[local], 0, 0);
                sourceHud[1] = rootAddress;
                isaac_lan_crafting_screen_width = nullptr;
                verify(hudFor[local], hudFor[next], 0);
                isaac_lan_crafting_screen_width = &screenWidth;
                isaac_lan_crafting_screen_height = nullptr;
                verify(hudFor[local], hudFor[next], 0);
                isaac_lan_crafting_screen_height = &screenHeight;
                const auto sourcePlayer = sourceHud[0];
                sourceHud[0] = 0;
                verify(hudFor[local], 0, 0);
                sourceHud[0] = sourcePlayer;
                isaac_lan_crafting_get_active_item = nullptr;
                verify(hudFor[local], 0, hudFor[local]);
                isaac_lan_crafting_get_active_item = reinterpret_cast<void*>(activeItemFixture);
                isaac::runtime::target = local;
                verify(hudFor[local], 0, hudFor[local]);
                for (int invalid : {-2, 4}) {
                    isaac::runtime::target = invalid;
                    for (auto hud : hudFor)
                        verify(hud, 0, 0);
                }
                isaac::runtime::target = next;
                for (int invalid : {-1, 4}) {
                    isaac::runtime::local = invalid;
                    verify(hudFor[local], 0, 0);
                }
                verify(0, 0, 0);
            }
        std::puts("PASS production x86 HUD: next bag with full bottom-right local pocket; "
                  "2/3/4 seats, screen size and HUD offset anchors; alpha, GPR, other SSE and "
                  "flags preserved; ordinary passthrough, remote/invalid hidden; no mutation");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

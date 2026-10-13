// Execute the production x86 visibility detour without loading the game.
#include "test_support.h"
#include <array>
#include <cstdint>
#include <cstring>
#include <cstdio>
namespace isaac::runtime {
int target = -1;
int craftingBagViewTarget() {
    return target;
}
} // namespace isaac::runtime
extern "C" {
extern void* isaac_lan_crafting_hud_original;
void isaac_lan_crafting_hud_thunk();
unsigned hudCalls = 0;
std::uintptr_t observedHud = 0, observedPosition = 0;
float observedScale = 0;
__attribute__((naked)) void originalHudFixture() {
    __asm__ __volatile__("incl _hudCalls\n\tmovl %ecx, _observedHud\n\t"
                         "movl 4(%esp), %eax\n\tmovl %eax, _observedPosition\n\t"
                         "movss %xmm2, _observedScale\n\tret $4");
}
}
void invoke(std::uintptr_t* hud) {
    const std::array<float, 2> position{12, 34};
    const float scale = 0.75f;
    auto receiver = reinterpret_cast<std::uintptr_t>(hud);
    auto argument = reinterpret_cast<std::uintptr_t>(&position);
    __asm__ __volatile__("movss %2, %%xmm2\n\tpushl %%eax\n\t"
                         "call _isaac_lan_crafting_hud_thunk"
                         : "+c"(receiver), "+a"(argument)
                         : "m"(scale)
                         : "edx", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5", "xmm6", "xmm7",
                           "memory", "cc");
    if (hudCalls) {
        require(observedHud == reinterpret_cast<std::uintptr_t>(hud), "ECX receiver changed");
        require(observedPosition == reinterpret_cast<std::uintptr_t>(&position),
                "Stack argument changed");
        require(observedScale == scale, "SSE scale changed");
    }
}
int main() {
    try {
        isaac_lan_crafting_hud_original = reinterpret_cast<void*>(originalHudFixture);
        alignas(16) std::array<std::uint8_t, 0x2200> player{};
        std::uintptr_t hud = reinterpret_cast<std::uintptr_t>(player.data());
        for (int target : {-2, -1, 0, 1, 2, 3}) {
            isaac::runtime::target = target;
            for (int slot = 0; slot < 4; ++slot)
                for (bool ghost : {false, true}) {
                    *reinterpret_cast<int*>(player.data() + 0x1618) = slot + 1;
                    player[0x20a9] = ghost;
                    const auto before = player;
                    hudCalls = 0;
                    invoke(&hud);
                    require(hudCalls == unsigned(target == -1 || (target == slot && !ghost)),
                            "Native HUD exposed hidden materials or suppressed permitted target");
                    require(player == before &&
                                hud == reinterpret_cast<std::uintptr_t>(player.data()),
                            "Rendering changed authoritative materials or HUD ownership");
                }
        }
        std::puts(
            "PASS production x86 bag HUD detour: receiver, stack, SSE, visibility and no mutation");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

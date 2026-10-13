// Compile the real adapter in this translation unit to test its caller fence.
#include "test_support.h"
#include "engine/versions/j460/challenge_hud.cpp"
#include <cstdio>
namespace isaac::runtime {
std::array<int, 2> goal{-1, -1};
std::array<int, 2> challengeDestination() {
    return goal;
}
} // namespace isaac::runtime
extern "C" {
unsigned destinationCalls = 0, observedECX = 0;
float observedDestinationScale = 0;
__attribute__((naked)) void destinationFixture() {
    __asm__ __volatile__("incl _destinationCalls\n\tmovl %ecx, _observedECX\n\t"
                         "movss %xmm2, _observedDestinationScale\n\tret");
}
__attribute__((naked, fastcall)) void invokeDestination(void*) {
    __asm__ __volatile__("pushl %ebp\n\tmovl %ecx, %ebp\n\t"
                         "movl $0xaabbcc00, %ecx\n\t"
                         "movl $0x3f400000, %eax\n\tmovd %eax, %xmm2\n\t"
                         "call _isaac_lan_destination_thunk\n\tpopl %ebp\n\tret");
}
}
const void* __attribute__((thiscall)) paramsFixture(void* game) {
    return game;
}
int main() {
    try {
        using namespace isaac::presentation;
        isaac_lan_destination_original = reinterpret_cast<void*>(destinationFixture);
        originalParams = paramsFixture;
        base = 0x400000;
        const auto site = base + isaac::engine::j460::entry::hUDChallengeParamsReturn;
        std::array<std::uint8_t, 256> frame{};
        auto* ebp = frame.data() + 200;
        for (bool active : {false, true, false}) {
            isaac::runtime::goal = active ? std::array{11, 0} : std::array{-1, -1};
            frame.fill(0x7a);
            const auto before = frame;
            destinationCalls = 0;
            invokeDestination(ebp);
            require(destinationCalls == 1 && observedECX == (active ? 0xaabbcc01u : 0xaabbcc00u),
                    "Native destination presence did not preserve unrelated ECX bits");
            require(observedDestinationScale == 0.75f, "Destination detour changed SSE state");
            for (unsigned i = 0; i < frame.size(); ++i)
                require(frame[i] == (active && i == 200 - 0xa2 ? 1 : before[i]),
                        "Destination detour touched unrelated HUD frame data");
            require(paramsForCaller(ebp, site - 1) == ebp && paramsForCaller(ebp, site + 1) == ebp,
                    "Visual goal leaked into native gameplay parameters");
            const auto* value = paramsForCaller(ebp, site);
            if (active) {
                const auto* scalars = static_cast<const std::uint32_t*>(value);
                require(scalars[0x40 / 4] == 11 && scalars[0x80 / 4] == 0 && scalars[0x74 / 4] == 0,
                        "Native HUD did not receive the Lamb destination");
            } else
                require(value == ebp, "Ordinary challenges lost their native parameters");
        }
        std::puts("PASS production x86 destination HUD detour, native caller fence and cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

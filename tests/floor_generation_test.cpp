#include "engine/versions/j460/floor_generation.cpp"
#include "test_support.h"
#include <array>
#include <cstdio>

extern "C" {
unsigned observedFloorFlags = 0, observedFloorGame = 0, observedFloorECX = 0;
unsigned observedFloorEBX = 0, observedFloorEDX = 0, observedFloorCalls = 0;
float observedFloorScale = 0;
__attribute__((naked)) void floorReturn() {
    __asm__ __volatile__("pushfl\n\tpopl _observedFloorFlags\n\t"
                         "movl %eax, _observedFloorGame\n\tmovl %ecx, _observedFloorECX\n\t"
                         "movl %ebx, _observedFloorEBX\n\tmovl %edx, _observedFloorEDX\n\t"
                         "movss %xmm2, _observedFloorScale\n\tincl _observedFloorCalls\n\tret");
}
#define INVOKE_FLOOR(thunk)                                                                        \
    __asm__ __volatile__("pushl %ebx\n\tmovl %ecx, %eax\n\tmovl $0xaabbccdd, %ebx\n\t"             \
                         "movl $0x3f400000, %edx\n\tmovd %edx, %xmm2\n\t"                          \
                         "call _" #thunk "\n\tpopl %ebx\n\tret")
__attribute__((naked, fastcall)) void invokeFloorCount(void*) {
    INVOKE_FLOOR(isaac_lan_floor_count);
}
__attribute__((naked, fastcall)) void invokeFloorShape(void*) {
    INVOKE_FLOOR(isaac_lan_floor_shape);
}
#undef INVOKE_FLOOR
}

int main() {
    using namespace isaac::engine;
    constexpr unsigned zeroFlag = 0x40;
    std::array<std::uint32_t, (j460::layout::game::challenge + 4) / 4> game{};
    bool active = false;
    static bool requested = false;
    useLargeFloor = [] { return requested; };
    isaac_lan_floor_count_return = reinterpret_cast<void*>(floorReturn);
    isaac_lan_floor_shape_return = reinterpret_cast<void*>(floorReturn);
    for (auto invoke : {invokeFloorCount, invokeFloorShape})
        for (const auto challenge : {0u, 21u, 22u}) {
            game.fill(0xaabbccdd);
            game[j460::layout::game::challenge / 4] = challenge;
            const auto before = game;
            for (active = false;; active = true) {
                requested = active;
                observedFloorCalls = 0;
                invoke(game.data());
                require(((observedFloorFlags & zeroFlag) != 0) == (active || challenge == 21),
                        "Native or LAN floor generation selected the wrong branch");
                require(!active || (observedFloorFlags & arithmeticFlags) == equalFlags,
                        "Extended floor comparison flags were not an equal comparison");
                require(observedFloorCalls == 1 && game == before &&
                            observedFloorGame == reinterpret_cast<unsigned>(game.data()) &&
                            observedFloorECX == observedFloorGame &&
                            observedFloorEBX == 0xaabbccdd && observedFloorEDX == 0x3f400000 &&
                            observedFloorScale == 0.75f,
                        "Floor comparison changed native state, registers or SSE state");
                if (active)
                    break;
            }
        }
    std::puts(
        "PASS both native floor branches, original challenges, registers and unchanged game state");
}

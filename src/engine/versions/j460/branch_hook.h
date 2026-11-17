#pragma once
#include <cstdint>

namespace isaac::engine::j460::branch {
inline constexpr std::uint32_t arithmeticFlags = 0x8d5, equalFlags = 0x44;
// pushad follows pushfd: EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX, EFLAGS.
inline void selectEqual(std::uint32_t* registers) {
    registers[8] = (registers[8] & ~arithmeticFlags) | equalFlags;
}
} // namespace isaac::engine::j460::branch

// Inline branch observers preserve every GPR, flags and SSE register. The
// callback receives the saved register block and may change its named fields.
#define ISAAC_LAN_BRANCH_CALL(callback)                                                            \
    "pushfl\n\tpushal\n\tsubl $128, %%esp\n\t"                                                     \
    "movups %%xmm0, (%%esp)\n\tmovups %%xmm1, 16(%%esp)\n\t"                                       \
    "movups %%xmm2, 32(%%esp)\n\tmovups %%xmm3, 48(%%esp)\n\t"                                     \
    "movups %%xmm4, 64(%%esp)\n\tmovups %%xmm5, 80(%%esp)\n\t"                                     \
    "movups %%xmm6, 96(%%esp)\n\tmovups %%xmm7, 112(%%esp)\n\t"                                    \
    "leal 128(%%esp), %%eax\n\tpushl %%eax\n\tcall _" #callback "\n\t"                             \
    "addl $4, %%esp\n\tmovups (%%esp), %%xmm0\n\tmovups 16(%%esp), %%xmm1\n\t"                     \
    "movups 32(%%esp), %%xmm2\n\tmovups 48(%%esp), %%xmm3\n\t"                                     \
    "movups 64(%%esp), %%xmm4\n\tmovups 80(%%esp), %%xmm5\n\t"                                     \
    "movups 96(%%esp), %%xmm6\n\tmovups 112(%%esp), %%xmm7\n\t"                                    \
    "addl $128, %%esp\n\tpopal\n\tpopfl\n\t"

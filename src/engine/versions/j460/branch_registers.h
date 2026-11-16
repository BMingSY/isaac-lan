#pragma once

// A private continuation, EFLAGS, pushad, then all eight SSE registers.
// The continuation is at ESP+164 until this frame is restored by RET.
#define ISAAC_LAN_BRANCH_SAVE                                                                      \
    "pushl $0\n\tpushfl\n\tpushal\n\tsubl $128, %esp\n\t"                                          \
    "movups %xmm0, 0(%esp)\n\tmovups %xmm1, 16(%esp)\n\t"                                          \
    "movups %xmm2, 32(%esp)\n\tmovups %xmm3, 48(%esp)\n\t"                                         \
    "movups %xmm4, 64(%esp)\n\tmovups %xmm5, 80(%esp)\n\t"                                         \
    "movups %xmm6, 96(%esp)\n\tmovups %xmm7, 112(%esp)\n\t"
#define ISAAC_LAN_BRANCH_RESTORE                                                                   \
    "movups 0(%esp), %xmm0\n\tmovups 16(%esp), %xmm1\n\t"                                          \
    "movups 32(%esp), %xmm2\n\tmovups 48(%esp), %xmm3\n\t"                                         \
    "movups 64(%esp), %xmm4\n\tmovups 80(%esp), %xmm5\n\t"                                         \
    "movups 96(%esp), %xmm6\n\tmovups 112(%esp), %xmm7\n\t"                                        \
    "addl $128, %esp\n\tpopal\n\tpopfl\n\tret"

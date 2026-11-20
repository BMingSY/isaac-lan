#pragma once
#include <array>
#include <cstdint>

namespace isaac::engine::native_branch {
enum Register : unsigned { edi, esi, ebp, esp, ebx, edx, ecx, eax, flags, continuation };
using Frame = std::array<std::uintptr_t, continuation + 1>;
static_assert(sizeof(std::uintptr_t) == 4);
} // namespace isaac::engine::native_branch

// A private continuation, EFLAGS and pushad are followed by an aligned FXSAVE
// area. EAX points to Frame when SAVE returns; prepare functions may change only
// the explicitly bound registers or continuation before RESTORE resumes native.
#define ISAAC_LAN_NATIVE_BRANCH_SAVE                                                               \
    "pushl $0\n\tpushfl\n\tpushal\n\tmovl %esp, %eax\n\t"                                          \
    "andl $-16, %esp\n\tsubl $528, %esp\n\tmovl %eax, 512(%esp)\n\tfxsave (%esp)\n\t"
#define ISAAC_LAN_NATIVE_BRANCH_RESTORE                                                            \
    "fxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\tret"

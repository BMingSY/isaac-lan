#include "native_branch.h"
#include <cstring>

extern "C" {
void* native_branch_target = nullptr;
unsigned native_branch_inputs[8]{}, native_branch_outputs[8]{}, native_branch_flags = 0;
unsigned native_branch_before = 0, native_branch_after = 0;
alignas(16) unsigned char native_branch_caller_fp[512]{}, native_branch_initial_fp[512]{};
alignas(16) unsigned char native_branch_observed_fp[512]{};
__attribute__((naked)) void native_branch_invoke() {
    __asm__ __volatile__(
        "pushfl\n\tpushal\n\tmovl %esp, _native_branch_before\n\t"
        "fxsave _native_branch_caller_fp\n\tfninit\n\tfld1\n\tpcmpeqd %xmm7, %xmm7\n\t"
        "fxsave _native_branch_initial_fp\n\t"
        "movl _native_branch_inputs, %edi\n\tmovl _native_branch_inputs+4, %esi\n\t"
        "movl _native_branch_inputs+8, %ebp\n\tmovl _native_branch_inputs+16, %ebx\n\t"
        "movl _native_branch_inputs+20, %edx\n\tmovl _native_branch_inputs+24, %ecx\n\t"
        "movl _native_branch_inputs+28, %eax\n\tcmpl %eax, %eax\n\tstc\n\t"
        "call *_native_branch_target\n\tmovl %esp, _native_branch_after\n\t"
        "pushfl\n\tpushal\n\tmovl %esp, %esi\n\tmovl $_native_branch_outputs, %edi\n\t"
        "movl $8, %ecx\n\tcld\n\trep movsl\n\tmovl 32(%esp), %eax\n\t"
        "movl %eax, _native_branch_flags\n\tfxsave _native_branch_observed_fp\n\t"
        "fxrstor _native_branch_caller_fp\n\tmovl _native_branch_before, %esp\n\t"
        "popal\n\tpopfl\n\tret");
}
}
namespace native_fixture {
BranchResult branch(void* target, const Registers& registers) {
    native_branch_target = target;
    std::memcpy(native_branch_inputs, registers.data(), sizeof(native_branch_inputs));
    native_branch_invoke();
    BranchResult result;
    std::memcpy(result.registers.data(), native_branch_outputs, sizeof(native_branch_outputs));
    result.flags = native_branch_flags;
    result.balanced = native_branch_before == native_branch_after;
    result.floatingPreserved =
        std::memcmp(native_branch_initial_fp, native_branch_observed_fp, 28) == 0 &&
        std::memcmp(native_branch_initial_fp + 32, native_branch_observed_fp + 32, 10) == 0 &&
        std::memcmp(native_branch_initial_fp + 160, native_branch_observed_fp + 160, 128) == 0;
    return result;
}
} // namespace native_fixture

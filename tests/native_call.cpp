#include "native_call.h"
#include <algorithm>
#include <array>

extern "C" {
void* native_fixture_target = nullptr;
void* native_fixture_receiver = nullptr;
const std::uint32_t* native_fixture_arguments = nullptr;
unsigned native_fixture_count = 0;
unsigned native_fixture_before = 0, native_fixture_after = 0, native_fixture_result = 0;
unsigned native_fixture_saved[4]{};
__attribute__((naked)) void native_fixture_invoke() {
    __asm__ __volatile__(
        "pushal\n\tmovl %esp, _native_fixture_before\n\t"
        "movl _native_fixture_count, %ecx\n\tmovl _native_fixture_arguments, %edx\n\t"
        "testl %ecx, %ecx\n\tjz 2f\n\t"
        "1:\n\tdecl %ecx\n\tpushl (%edx,%ecx,4)\n\ttestl %ecx, %ecx\n\tjnz 1b\n\t"
        "2:\n\tmovl _native_fixture_receiver, %ecx\n\t"
        "movl $0x11223344, %ebx\n\tmovl $0x22334455, %esi\n\t"
        "movl $0x33445566, %edi\n\tmovl $0x44556677, %ebp\n\t"
        "call *_native_fixture_target\n\tmovl %eax, _native_fixture_result\n\t"
        "movl %esp, _native_fixture_after\n\tmovl %ebx, _native_fixture_saved\n\t"
        "movl %esi, _native_fixture_saved+4\n\tmovl %edi, _native_fixture_saved+8\n\t"
        "movl %ebp, _native_fixture_saved+12\n\tmovl _native_fixture_before, %esp\n\t"
        "popal\n\tret");
}
}
namespace native_fixture {
CallResult call(void* target, void* receiver, std::initializer_list<std::uint32_t> arguments) {
    // A hooked card/pill can call another native fixture. Keep the outer
    // invocation's recovery stack alive across that nested probe.
    const auto previousStack = native_fixture_before;
    native_fixture_target = target;
    native_fixture_receiver = receiver;
    native_fixture_arguments = arguments.begin();
    native_fixture_count = arguments.size();
    native_fixture_invoke();
    constexpr std::array expected{0x11223344u, 0x22334455u, 0x33445566u, 0x44556677u};
    const CallResult result{native_fixture_result, native_fixture_before == native_fixture_after,
                            std::equal(expected.begin(), expected.end(), native_fixture_saved)};
    native_fixture_before = previousStack;
    return result;
}
} // namespace native_fixture

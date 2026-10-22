// Execute the real J460 leaf through MinHook, including its stronger register ABI.
#include "engine/versions/j460/spawner_links.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "test_support.h"
#include <MinHook.h>
#include <windows.h>
#include <array>
#include <cstring>
#include <set>
#include <vector>

namespace {
using namespace isaac::engine::j460;
struct Node {
    std::array<std::uint32_t, (layout::entity::spawner + sizeof(void*)) / 4> words{};
};
void*& next(void* node) {
    return *reinterpret_cast<void**>(static_cast<char*>(node) + layout::entity::spawner);
}
struct Registers {
    std::array<std::uint32_t, 8> integer{};
    std::array<std::array<std::uint32_t, 4>, 8> xmm{}, expected{};
};
static_assert(offsetof(Registers, xmm) == 32 && offsetof(Registers, expected) == 160);
__attribute__((naked, cdecl)) void invoke(void*, void*, unsigned, Registers*) {
    asm volatile("push %ebp\n\t"
                 "mov %esp, %ebp\n\t"
                 "push %ebx\n\t"
                 "push %esi\n\t"
                 "push %edi\n\t"
                 "mov 20(%ebp), %eax\n\t"
                 "movdqu 160(%eax), %xmm0\n\t"
                 "movdqu 176(%eax), %xmm1\n\t"
                 "movdqu 192(%eax), %xmm2\n\t"
                 "movdqu 208(%eax), %xmm3\n\t"
                 "movdqu 224(%eax), %xmm4\n\t"
                 "movdqu 240(%eax), %xmm5\n\t"
                 "movdqu 256(%eax), %xmm6\n\t"
                 "movdqu 272(%eax), %xmm7\n\t"
                 "mov 12(%ebp), %ecx\n\t"
                 "mov 16(%ebp), %edx\n\t"
                 "mov $0x12345678, %ebx\n\t"
                 "mov $0x23456789, %esi\n\t"
                 "mov $0x3456789a, %edi\n\t"
                 "call *8(%ebp)\n\t"
                 "pushf\n\t"
                 "push %edx\n\t"
                 "push %ecx\n\t"
                 "push %eax\n\t"
                 "mov 20(%ebp), %eax\n\t"
                 "pop 0(%eax)\n\t"
                 "pop 4(%eax)\n\t"
                 "pop 8(%eax)\n\t"
                 "pop 24(%eax)\n\t"
                 "mov %ebx, 12(%eax)\n\t"
                 "mov %esi, 16(%eax)\n\t"
                 "mov %edi, 20(%eax)\n\t"
                 "movdqu %xmm0, 32(%eax)\n\t"
                 "movdqu %xmm1, 48(%eax)\n\t"
                 "movdqu %xmm2, 64(%eax)\n\t"
                 "movdqu %xmm3, 80(%eax)\n\t"
                 "movdqu %xmm4, 96(%eax)\n\t"
                 "movdqu %xmm5, 112(%eax)\n\t"
                 "movdqu %xmm6, 128(%eax)\n\t"
                 "movdqu %xmm7, 144(%eax)\n\t"
                 "pop %edi\n\t"
                 "pop %esi\n\t"
                 "pop %ebx\n\t"
                 "pop %ebp\n\t"
                 "ret");
}
constexpr std::array<unsigned char, 32> nativeLeaf{
    0x8b, 0x81, 0xc8, 0x03, 0x00, 0x00, 0x85, 0xc0, 0x74, 0x12, 0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00,
    0x8b, 0xc8, 0x8b, 0x81, 0xc8, 0x03, 0x00, 0x00, 0x85, 0xc0, 0x75, 0xf4, 0x8b, 0xc1, 0xc3, 0xcc};
struct Fixture {
    void* image = VirtualAlloc(nullptr, entry::entitySpawnerRoot + nativeLeaf.size(),
                               MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    void* target = nullptr;
    Fixture() {
        require(image != nullptr, "Cannot allocate native leaf fixture");
        target = static_cast<char*>(image) + entry::entitySpawnerRoot;
        std::memcpy(target, nativeLeaf.data(), nativeLeaf.size());
        require(FlushInstructionCache(GetCurrentProcess(), target, nativeLeaf.size()),
                "Cannot publish native leaf fixture");
        require(MH_Initialize() == MH_OK, "Cannot initialize native hook fixture");
    }
    ~Fixture() {
        MH_Uninitialize();
        VirtualFree(image, 0, MEM_RELEASE);
    }
    void install() {
        require(spawner_links::install(reinterpret_cast<std::uintptr_t>(image)),
                "Cannot install actual spawner hook");
    }
};
void check(void* target, void* input, void* expected, unsigned edx) {
    Registers registers;
    for (unsigned i = 0; i < registers.expected.size(); ++i)
        for (unsigned j = 0; j < registers.expected[i].size(); ++j)
            registers.expected[i][j] = 0xabc00000u + 16 * i + j;
    invoke(target, input, edx, &registers);
    const auto pointer = reinterpret_cast<std::uintptr_t>(expected);
    require(registers.integer[0] == pointer && registers.integer[1] == pointer,
            "Spawner lookup changed EAX/ECX root contract");
    require(registers.integer[2] == edx && registers.integer[3] == 0x12345678 &&
                registers.integer[4] == 0x23456789 && registers.integer[5] == 0x3456789a,
            "Spawner lookup clobbered live EDX or callee registers");
    constexpr unsigned comparedFlags = 0x8c5, nullLinkFlags = 0x44;
    require((registers.integer[6] & comparedFlags) == nullLinkFlags,
            "Spawner lookup changed native null-link flags");
    require(registers.xmm == registers.expected, "Spawner lookup clobbered XMM state");
}
void validAbi() {
    Fixture fixture;
    std::array<Node, 4> nodes{};
    for (unsigned i = 0; i + 1 < nodes.size(); ++i)
        next(&nodes[i]) = &nodes[i + 1];
    check(fixture.target, &nodes.front(), &nodes.back(), 0x12345601);
    check(fixture.target, &nodes.back(), &nodes.back(), 0x39);
    fixture.install();
    const auto before = nodes;
    for (unsigned repeat = 0; repeat < 3; ++repeat) {
        check(fixture.target, &nodes.front(), &nodes.back(), 0x12345601);
        check(fixture.target, &nodes.back(), &nodes.back(), 0x39);
    }
    require(std::memcmp(nodes.data(), before.data(), sizeof(nodes)) == 0,
            "Query changed native links or observer storage");
}
void graphOracle() {
    Fixture fixture;
    fixture.install();
    std::array<Node, 4> nodes{};
    // Every four-node functional graph, compared to a set-based independent oracle.
    for (unsigned graph = 0; graph < 625; ++graph) {
        unsigned remaining = graph;
        for (auto& node : nodes) {
            const auto link = remaining % 5;
            next(&node) = link ? &nodes[link - 1] : nullptr;
            remaining /= 5;
        }
        const auto before = nodes;
        for (auto& input : nodes) {
            void* root = &input;
            std::set<void*> seen;
            for (;;) {
                if (!seen.insert(root).second) {
                    root = &input;
                    break;
                }
                if (!next(root))
                    break;
                root = next(root);
            }
            check(fixture.target, &input, root, 0x98765401);
        }
        require(std::memcmp(nodes.data(), before.data(), sizeof(nodes)) == 0,
                "Cyclic query rewrote an EntityPtr or observer");
    }
}
void lifecycle() {
    Fixture fixture;
    fixture.install();
    std::vector<Node> nodes(4096);
    for (unsigned i = 0; i + 1 < nodes.size(); ++i)
        next(&nodes[i]) = &nodes[i + 1];
    check(fixture.target, &nodes.front(), &nodes.back(), 0x39);
    next(&nodes.back()) = &nodes[nodes.size() / 2];
    check(fixture.target, &nodes.front(), &nodes.front(), 0x12345601);
    // Model the native owner clearing references and reusing the same storage.
    for (auto& node : nodes)
        next(&node) = nullptr;
    check(fixture.target, &nodes.front(), &nodes.front(), 0x39);
    next(&nodes.front()) = &nodes.back();
    check(fixture.target, &nodes.front(), &nodes.back(), 0x12345601);
}
} // namespace
int main(int argc, char** argv) {
    static_assert(sizeof(void*) == 4);
    return runTests(
        argc, argv,
        {{"valid-abi", validAbi}, {"graph-oracle", graphOracle}, {"lifecycle", lifecycle}});
}

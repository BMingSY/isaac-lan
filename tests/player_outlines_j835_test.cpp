#include "test_support.h"
#include "native_call.h"
#include "engine/versions/j835/player_outlines.cpp"
#include <climits>
#include <iostream>
#include <vector>

namespace outlines = isaac::presentation::outlines;
extern "C" {
unsigned char outlineFrame[256]{}, outlinePlayer[0x1600]{};
float outlineOffset[2]{13, 27};
void* outlineTarget = nullptr;
unsigned outlineChoice = 0, outlineRegisters[8]{}, outlineFlags = 0;
unsigned outlineBefore = 0, outlineAfter = 0;
alignas(16) unsigned char outlineInitialFloating[512]{}, outlineFloating[512]{};
__attribute__((naked)) void outlineObserved() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, %esi\n\t"
                         "movl $_outlineRegisters, %edi\n\tmovl $8, %ecx\n\tcld\n\trep movsl\n\t"
                         "movl 32(%esp), %eax\n\tmovl %eax, _outlineFlags\n\t"
                         "fxsave _outlineFloating\n\tpopal\n\tpopfl\n\tret");
}
__attribute__((naked)) void outlineOriginal() {
    __asm__ __volatile__("movl $17, _outlineChoice\n\tjmp _outlineObserved");
}
__attribute__((naked)) void outlineColored() {
    __asm__ __volatile__("movl $23, _outlineChoice\n\tjmp _outlineObserved");
}
__attribute__((naked)) void invokeOutline() {
    __asm__ __volatile__(
        "pushfl\n\tpushal\n\tmovl %esp, _outlineBefore\n\tleal _outlineFrame+128, %ebp\n\t"
        "movl $_outlinePlayer, %edi\n\tmovl $_outlineOffset, %esi\n\t"
        "movl $0x12345678, %eax\n\tmovl $0x22334455, %edx\n\tmovl $0x33445566, %ebx\n\t"
        "movl $0x87654321, %ecx\n\tpcmpeqd %xmm7, %xmm7\n\tfld1\n\t"
        "fxsave _outlineInitialFloating\n\tcmpl %eax, %eax\n\tstc\n\tcall *_outlineTarget\n\t"
        "movl %esp, _outlineAfter\n\tmovl _outlineBefore, %esp\n\tfstp "
        "%st(0)\n\tpopal\n\tpopfl\n\tret");
}
}
namespace {
using Address = std::uintptr_t;
using Vector = std::array<float, 2>;
unsigned char* image = nullptr;
unsigned nativePushes = 0, throwOnDraw = 0;
std::vector<Vector> draws;
outlines::Color pushedColor{};
std::string lastError;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* value) {
    return reinterpret_cast<Address>(value);
}
void jump(unsigned char* target, void* function) {
    std::memset(target, 0x90, 16);
    target[0] = 0xe9;
    auto delta = address(function) - address(target + 5);
    std::memcpy(target + 1, &delta, 4);
}
void __attribute__((fastcall)) pushColor(const outlines::Color* color, void*) {
    pushedColor = *color;
    ++nativePushes;
    auto* stack = image + 0x7fec10;
    // Model native growth retaining ownership after the logical pop.
    field<unsigned>(stack, 4) = 0xabcdef;
    field<unsigned>(stack, 8) = 64;
    ++field<unsigned>(stack, 0x10);
}
void __attribute__((fastcall)) renderGhost(void* player, void*, const Vector* offset) {
    require(player == outlinePlayer && field<unsigned>(image, 0x7fec20) > 0,
            "Ghost native draw lost receiver or color scope");
    draws.push_back(*offset);
    field<Vector>(player, 0x19c) = *offset;
    // Helpers and native rendering may clobber every caller-saved FP register.
    unsigned control;
    __asm__ __volatile__("stmxcsr %0" : "=m"(control));
    control ^= 0x6000;
    __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0" : : "m"(control) : "xmm7");
    if (throwOnDraw && draws.size() == throwOnDraw)
        throw std::runtime_error("Fixture ghost render failure");
}
void controller(int value) {
    field<int>(outlinePlayer, 0x154c) = value;
}
void expect(unsigned choice, bool colorReceiver = false) {
    invokeOutline();
    require(outlineChoice == choice && outlineBefore == outlineAfter,
            "Outline continuation or stack balance changed");
    require(outlineRegisters[0] == address(outlinePlayer) &&
                outlineRegisters[1] == address(outlineOffset) &&
                outlineRegisters[2] == address(outlineFrame + 128) &&
                outlineRegisters[4] == 0x33445566 && outlineRegisters[5] == 0x22334455 &&
                outlineRegisters[6] ==
                    (colorReceiver ? address(outlineFrame + 128 - 0x3c) : 0x87654321) &&
                outlineRegisters[7] == 0x12345678 && (outlineFlags & 0x41) == 0x41,
            "Outline gate damaged GPRs or flags");
    require(std::memcmp(outlineInitialFloating, outlineFloating, 24) == 0 &&
                std::memcmp(outlineInitialFloating + 24, outlineFloating + 24, 4) == 0 &&
                std::memcmp(outlineInitialFloating + 32, outlineFloating + 32, 10) == 0 &&
                std::memcmp(outlineInitialFloating + 160, outlineFloating + 160, 128) == 0,
            "Outline gate damaged x87, MXCSR or SSE state");
}
void installHooks() {
    const std::array<unsigned, 3> gates{0x353a89, 0x35382e, 0x353c6c};
    for (auto rva : gates)
        jump(image + rva, reinterpret_cast<void*>(outlineOriginal));
    jump(image + 0x353aef, reinterpret_cast<void*>(outlineColored));
    jump(image + 0x353894, reinterpret_cast<void*>(outlineColored));
    jump(image + 0x2420, reinterpret_cast<void*>(pushColor));
    jump(image + 0x288480, reinterpret_cast<void*>(renderGhost));
    FlushInstructionCache(GetCurrentProcess(), image, 0x800000);
    require(!outlines::install(0), "Null image installed outline hooks");
    for (unsigned conflict = 0; conflict < gates.size(); ++conflict) {
        const auto target = image + gates[conflict];
        require(MH_CreateHook(target, reinterpret_cast<void*>(outlineOriginal), nullptr) == MH_OK,
                "Create foreign outline hook");
        require(!outlines::install(address(image)) && !outlines::image && !outlines::installed,
                "Partial outline install survived failure");
        require(MH_CreateHook(target, reinterpret_cast<void*>(outlineOriginal), nullptr) ==
                    MH_ERROR_ALREADY_CREATED,
                "Outline rollback removed a foreign hook");
        for (unsigned i = 0; i < conflict; ++i) {
            require(!outlines::boundaries[i].original &&
                        MH_CreateHook(image + gates[i], reinterpret_cast<void*>(outlineOriginal),
                                      nullptr) == MH_OK,
                    "Failed install leaked an earlier hook or trampoline");
            require(MH_RemoveHook(image + gates[i]) == MH_OK, "Remove rollback probe");
        }
        require(MH_RemoveHook(target) == MH_OK, "Remove foreign outline fixture");
    }
    require(outlines::install(address(image)) && !outlines::install(address(image)),
            "Outline retry or duplicate install failed");
}
} // namespace
namespace isaac::runtime {
void abort(const std::string& reason) {
    lastError = reason;
}
} // namespace isaac::runtime
int main() {
    try {
        image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, 0x800000, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate outline fixture");
        installHooks();
        auto& mainPass = outlineFrame[128 + 0xc];
        auto& hologram = outlineFrame[128 - 0x79];
        for (unsigned entry : {0x353a89u, 0x35382eu}) {
            outlineTarget = image + entry;
            std::memset(outlineFrame, 0x5a, sizeof(outlineFrame));
            mainPass = 1;
            hologram = 0;
            const auto untouched =
                std::vector<unsigned char>(std::begin(outlineFrame), std::end(outlineFrame));
            controller(1);
            expect(17);
            require(std::memcmp(outlineFrame, untouched.data(), untouched.size()) == 0,
                    "Inactive outline modified native locals");
            outlines::withPlayers(15, [&] {
                for (int c : {4, 2, 1, 3, 2}) {
                    controller(c);
                    expect(23, true);
                    auto expected = untouched;
                    const auto color = outlines::nativeColor(c - 1);
                    std::memcpy(expected.data() + 128 - 0x3c, color.data(), sizeof(color));
                    require(std::memcmp(outlineFrame, expected.data(), expected.size()) == 0,
                            "Outline changed locals beyond its complete temporary ColorMod");
                }
                for (int c : {0, -1, INT_MIN, 5, INT_MAX}) {
                    controller(c);
                    expect(17);
                }
                controller(2);
                mainPass = 0;
                expect(17);
                mainPass = 1;
                hologram = 1;
                expect(17);
                hologram = 0;
                outlines::withPlayers(1, [&] { expect(17); });
                expect(23, true);
                outlines::withPlayers(5, [&] { expect(17); });
                expect(23, true);
            });
            expect(17);
            try {
                outlines::withPlayers(3, [&] {
                    expect(23, true);
                    throw std::runtime_error("Fixture render interrupted");
                });
            } catch (const std::runtime_error&) {
            }
            require(!outlines::participants, "Interrupted room render retained LAN players");
        }
        outlineTarget = image + 0x353c6c;
        mainPass = 1;
        // Ghosts don't pass through the hologram local initialization.
        hologram = 0xa5;
        controller(3);
        field<Vector>(outlinePlayer, 0x19c) = {41, 59};
        const auto playerBefore =
            std::vector<unsigned char>(std::begin(outlinePlayer), std::end(outlinePlayer));
        expect(17);
        require(draws.empty() && nativePushes == 0, "Single player gained a ghost outline");
        outlines::withPlayers(15, [&] {
            for (unsigned priorColors : {0u, 2u}) {
                field<unsigned>(image, 0x7fec20) = priorColors;
                field<unsigned>(image, 0x7fec1c) = 0;
                draws.clear();
                expect(17);
                require(draws == std::vector<Vector>{{12, 27}, {13, 26}, {14, 27}, {13, 28}} &&
                            pushedColor == outlines::nativeColor(2) &&
                            field<unsigned>(image, 0x7fec20) == priorColors &&
                            field<unsigned>(image, 0x7fec1c) == 0 &&
                            field<unsigned>(image, 0x7fec14) == 0xabcdef &&
                            field<unsigned>(image, 0x7fec18) == 64 &&
                            std::memcmp(outlinePlayer, playerBefore.data(), playerBefore.size()) ==
                                0,
                        "Ghost outline lost native owner, previous colors, offsets or position");
                draws.clear();
                expect(17);
                require(draws.size() == 4 && field<unsigned>(image, 0x7fec20) == priorColors,
                        "Repeated ghost render accumulated color scopes");
            }
            draws.clear();
            throwOnDraw = 2;
            expect(17);
            require(draws.size() == 2 && field<unsigned>(image, 0x7fec20) == 2 &&
                        std::memcmp(outlinePlayer, playerBefore.data(), playerBefore.size()) == 0 &&
                        lastError == "Fixture ghost render failure",
                    "Failed ghost render leaked color stack or temporary position");
            throwOnDraw = 0;
            draws.clear();
            mainPass = 0;
            expect(17);
            require(draws.empty(), "Ghost afterimage gained an outline");
            mainPass = 1;
            outlines::withPlayers(1, [&] { expect(17); });
            require(draws.empty(), "Disconnected ghost retained its outline");
        });
        draws.clear();
        expect(17);
        require(draws.empty(), "Exited render scope retained ghost rendering");
        auto color = outlines::nativeColor(0);
        const auto pushAbi = native_fixture::call(image + 0x2420, &color, {});
        require(pushAbi.balanced && pushAbi.preserved && pushedColor == color,
                "Color push violated its ECX/no-stack-argument ABI");
        const Vector offset{7, 9};
        const auto renderAbi =
            native_fixture::call(image + 0x288480, outlinePlayer, {address(offset.data())});
        require(renderAbi.balanced && renderAbi.preserved && draws == std::vector<Vector>{offset},
                "Ghost draw violated thiscall stack or receiver ABI");
        for (unsigned gate : {0x353a89u, 0x35382eu, 0x353c6cu})
            require(MH_RemoveHook(image + gate) == MH_OK, "Remove owned outline fixture hook");
        require(MH_Uninitialize() == MH_OK, "Uninitialize outline fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout << "J835 outline eligibility, palette, ghost resources, x86 state and rollback "
                     "passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

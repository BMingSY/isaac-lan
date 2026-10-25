// Exercise the production x86 render boundaries using private memory only.
#include "test_support.h"
#include "engine/versions/j460/player_outlines.cpp"
#include <climits>
#include <cstdio>

namespace outlines = isaac::presentation::outlines;
namespace layout = isaac::engine::j460::layout;
extern "C" {
unsigned char outlineFrame[256]{}, outlinePlayer[layout::player::controller + sizeof(int)]{};
void (*outlineThunk)() = nullptr;
unsigned outlineECX = 0, outlineFlags = 0;
float outlineSSE = 0;
__attribute__((naked)) int outlineOriginal() {
    __asm__ __volatile__("pushfl\n\tpopl _outlineFlags\n\tmovl %ecx, _outlineECX\n\t"
                         "movss %xmm7, _outlineSSE\n\tmovl $17, %eax\n\tret");
}
__attribute__((naked)) int outlineDraw() {
    __asm__ __volatile__("pushfl\n\tpopl _outlineFlags\n\tmovl %ecx, _outlineECX\n\t"
                         "movss %xmm7, _outlineSSE\n\tmovl $23, %eax\n\tret");
}
__attribute__((naked)) int invokeOutline() {
    __asm__ __volatile__("pushl %ebp\n\tleal _outlineFrame+128, %ebp\n\t"
                         "pushl %ebx\n\tmovl $_outlinePlayer, %ebx\n\t"
                         "movl $0x87654321, %ecx\n\tmovl $0x3f400000, %eax\n\t"
                         "movd %eax, %xmm7\n\tstc\n\tcall *_outlineThunk\n\t"
                         "popl %ebx\n\tpopl %ebp\n\tret");
}
}
namespace {
unsigned colorCalls = 0;
outlines::Color* __attribute__((thiscall)) vanillaColor(void*, outlines::Color* out, void*) {
    ++colorCalls;
    out->fill(-1);
    return out;
}
void controller(int value) {
    *reinterpret_cast<int*>(outlinePlayer + layout::player::controller) = value;
}
void expectBoundary(int expected) {
    require(invokeOutline() == expected, "Wrong native outline continuation");
    require(outlineECX == 0x87654321 && (outlineFlags & 1) && outlineSSE == 0.75f,
            "Outline boundary corrupted general/SSE registers or flags");
}
void boundaries() {
    const std::array<void (*)(), 3> detours{outlines::isaac_lan_outline_body,
                                            outlines::isaac_lan_outline_special,
                                            outlines::isaac_lan_outline_ghost};
    outlines::image = 0;
    auto& mainPass = outlineFrame[128 + layout::playerRenderFrame::mainPass];
    auto& hologram = outlineFrame[128 + layout::playerRenderFrame::hologram];
    for (unsigned i = 0; i < detours.size(); ++i) {
        auto& boundary = outlines::boundaries[i];
        boundary.original = reinterpret_cast<void*>(outlineOriginal);
        boundary.draw = reinterpret_cast<unsigned>(outlineDraw);
        outlineThunk = detours[i];
        controller(1);
        mainPass = 1;
        hologram = 0;
        expectBoundary(17); // Single player / no LAN render scope.
        outlines::withPlayers(15, [&] {
            for (int c : {4, 2, 1, 3, 2}) { // Client-first reordered roster; twins reuse a slot.
                controller(c);
                expectBoundary(23);
            }
            for (int c : {0, -1, INT_MIN, 5, INT_MAX}) {
                controller(c);
                expectBoundary(17);
            }
            controller(2);
            mainPass = 0;
            expectBoundary(17); // Native afterimage pass follows vanilla.
            mainPass = 1;
            hologram = 1;
            expectBoundary(boundary.checksHologram ? 17 : 23);
            hologram = 0;
            outlines::withPlayers(1, [&] { expectBoundary(17); }); // Disconnect / nested view.
            expectBoundary(23);
            outlines::withPlayers(5, [&] { expectBoundary(17); }); // Inactive owner.
            expectBoundary(23);
        });
        expectBoundary(17);
        try {
            outlines::withPlayers(3, [&] {
                expectBoundary(23);
                throw std::runtime_error("render interrupted");
            });
        } catch (const std::runtime_error&) {
        }
        require(!outlines::participants, "Failed room render retained participants");
        expectBoundary(17);
    }
}
void colors() {
    outlines::originalColor = vanillaColor;
    outlines::Color result{};
    const auto caller = outlines::boundaries.front().colorReturn;
    controller(1);
    outlines::colorForCaller(nullptr, &result, outlinePlayer, caller);
    require(colorCalls == 1 && result[0] == -1, "Offline color was overridden");
    outlines::withPlayers(15, [&] {
        std::array<outlines::Color, 4> seen{};
        for (int c : {3, 1, 4, 2, 2}) {
            controller(c);
            for (const auto& boundary : outlines::boundaries) {
                const auto* returned =
                    outlines::colorForCaller(nullptr, &result, outlinePlayer, boundary.colorReturn);
                require(returned == &result && colorCalls == 1,
                        "LAN outline used native slot order");
                require(result[3] == 1 && result[4] == 0 && result[5] == 0 && result[6] == 0 &&
                            result[7] == 0 && result[0] == result[8] && result[1] == result[9] &&
                            result[2] == result[10],
                        "Invalid native ColorMod layout");
                seen[c - 1] = result;
            }
        }
        require(seen[0][0] > seen[0][1] && seen[0][0] > seen[0][2] && seen[1][2] > seen[1][0] &&
                    seen[1][2] > seen[1][1] && seen[2][0] > seen[2][2] && seen[2][1] > seen[2][2] &&
                    seen[3][1] > seen[3][0] && seen[3][1] > seen[3][2],
                "P1/P2/P3/P4 lost red/blue/yellow/green mapping");
        outlines::colorForCaller(nullptr, &result, outlinePlayer, 0);
        require(colorCalls == 2 && result[0] == -1, "Unrelated HUD or effect color was overridden");
        controller(5);
        outlines::colorForCaller(nullptr, &result, outlinePlayer, caller);
        require(colorCalls == 3 && result[0] == -1, "Unowned entity gained a color");
    });
}
} // namespace
int main() {
    try {
        boundaries();
        colors();
        std::puts("PASS player outline x86 gates, stable colors, render eligibility and cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

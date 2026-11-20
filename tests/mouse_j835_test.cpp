#include "test_support.h"
#include "engine/versions/j835/mouse_input.h"
#include "engine/versions/j835/entrypoints.h"
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <MinHook.h>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>

namespace {
namespace backend = isaac::engine::j835;
namespace mouse = isaac::engine::native_mouse;
using Address = std::uintptr_t;
constexpr unsigned imageSize = 0x890000;
unsigned char* image;
mouse::Aim physical;
mouse::Result mode = mouse::Result::passthrough;
mouse::Vector networkAim{2.4f, -1.6f};
std::array<unsigned char, 0x1600> player{}, secondPlayer{};
int height = 1080;
bool mouseDown = true, nestedCapture, sampleInsideRouter;
unsigned nativeCalls, routed;
constexpr std::ptrdiff_t activeOffset = -0x150, xOffset = -0x15c, yOffset = -0x158;
template <class T> T& field(void* pointer, std::ptrdiff_t offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(pointer) + offset);
}
Address base() {
    return reinterpret_cast<Address>(image);
}
void close(float actual, float expected, const char* message) {
    require(std::abs(actual - expected) < 0.00001f, message);
}
int __cdecl clientHeight() {
    return height;
}
struct Frame {
    std::array<unsigned char, 0x260> bytes;
    Frame() {
        bytes.fill(0xa5);
    }
    void* base() {
        return bytes.data() + 0x240;
    }
    bool& active() {
        return field<bool>(base(), activeOffset);
    }
    float& x() {
        return field<float>(base(), xOffset);
    }
    float& y() {
        return field<float>(base(), yOffset);
    }
};
struct Registers {
    unsigned ebx, esi;
    std::array<unsigned, 4> xmm7;
    unsigned mxcsr, flags;
    double x87;
};
static_assert(offsetof(Registers, xmm7) == 8 && offsetof(Registers, mxcsr) == 24 &&
              offsetof(Registers, flags) == 28 && offsetof(Registers, x87) == 32);
} // namespace
extern "C" {
void* mouse_fixture_resume;
unsigned mouse_fixture_resumes;
__attribute__((naked)) void mouse_fixture_end() {
    __asm__ __volatile__("pushfl\n\tincl _mouse_fixture_resumes\n\tpopfl\n\tret");
}
__attribute__((used, force_align_arg_pointer)) void __cdecl mouse_fixture_simulate(void* actor,
                                                                                   void* frame) {
    ++nativeCalls;
    if (nestedCapture) {
        nestedCapture = false;
        mouse::Vector inner;
        require(physical(secondPlayer.data(), &inner, false), "Nested physical query failed");
        close(inner.x, 4.0f, "Nested physical query changed its frame");
    }
    if (mouseDown && field<int>(actor, 0x154c) == 0) {
        // Independent native block fixture: pixel deltas are 52 and -26;
        // original Repentance applies 0.02 before the continuation.
        field<bool>(frame, activeOffset) = true;
        field<float>(frame, xOffset) = 1.04f;
        field<float>(frame, yOffset) = -0.52f;
    }
}
__attribute__((naked)) void mouse_fixture_begin() {
    __asm__ __volatile__("pushl %ebp\n\tpushl %edi\n\tcall _mouse_fixture_simulate\n\t"
                         "addl $8, %esp\n\tjmp *_mouse_fixture_resume");
}
// A native caller with live GPR/SSE/x87 state and an independent local frame.
__attribute__((naked)) void __cdecl mouse_fixture_run(void*, void*, void*, Registers*) {
    __asm__ __volatile__("pushl %ebp\n\tpushl %ebx\n\tpushl %esi\n\tpushl %edi\n\t"
                         "movl 20(%esp), %edi\n\tmovl 24(%esp), %ebp\n\t"
                         "movl $0x12345678, %ebx\n\tmovl $0x13572468, %esi\n\t"
                         "pcmpeqd %xmm7, %xmm7\n\tfld1\n\tcmpl %ebx, %ebx\n\tstc\n\t"
                         "call *28(%esp)\n\tmovl 32(%esp), %eax\n\t"
                         "movl %ebx, (%eax)\n\tmovl %esi, 4(%eax)\n\t"
                         "movups %xmm7, 8(%eax)\n\tstmxcsr 24(%eax)\n\t"
                         "pushfl\n\tpopl 28(%eax)\n\tfstpl 32(%eax)\n\t"
                         "popl %edi\n\tpopl %esi\n\tpopl %ebx\n\tpopl %ebp\n\tret");
}
} // extern "C"
namespace {
__attribute__((target("sse2"))) mouse::Result route(void* actor, mouse::Vector* aim) {
    require(actor == player.data(), "Inline mouse gate lost EDI player");
    ++routed;
    if (sampleInsideRouter) {
        mouse::Vector sample;
        require(physical(secondPlayer.data(), &sample, false), "Router physical bypass failed");
        close(sample.x, 4.0f, "Router physical sample changed scale");
    }
    *aim = networkAim;
    // A router is free to clobber caller-saved floating point state. Native
    // instructions following the boundary must retain their incoming state.
    const unsigned changedControl = 0x3f80;
    __asm__ __volatile__("fninit\n\tpxor %%xmm7, %%xmm7\n\tldmxcsr %0"
                         :
                         : "m"(changedControl)
                         : "xmm7");
    return mode;
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    field<std::uint32_t>(image, rva + 1) =
        static_cast<std::uint32_t>(reinterpret_cast<Address>(fn) - base() - rva - 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Create standalone mouse fixture");
    patch(backend::entry::playerMouseBegin, mouse_fixture_begin);
    patch(backend::entry::playerMouseEnd, mouse_fixture_end);
    patch(backend::entry::windowClientHeight, clientHeight);
    field<float>(image, 0x7aa930) = 270;
    mouse_fixture_resume = image + backend::entry::playerMouseEnd;
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    void* conflict = image + backend::entry::playerMouseEnd;
    require(MH_CreateHook(conflict, reinterpret_cast<void*>(mouse_fixture_end), nullptr) == MH_OK,
            "Create a foreign mouse boundary hook");
    require(!backend::mouse_input::install(base(), route, physical) && !physical,
            "Partial mouse installation must fail and clear its bypass");
    require(MH_RemoveHook(conflict) == MH_OK, "Mouse rollback removed another component's hook");
    require(backend::mouse_input::install(base(), route, physical) && physical,
            "Mouse installation did not recover from hook conflict");
}
void run(Frame& frame) {
    Registers registers{};
    unsigned control;
    __asm__ __volatile__("stmxcsr %0" : "=m"(control));
    mouse_fixture_run(player.data(), frame.base(), image + backend::entry::playerMouseBegin,
                      &registers);
    require(registers.ebx == 0x12345678 && registers.esi == 0x13572468,
            "Mouse boundary corrupted native callee-saved registers");
    require(registers.x87 == 1.0 && registers.mxcsr == control,
            "Mouse router corrupted live x87 or SSE control state");
    require(registers.xmm7 == std::array<unsigned, 4>{~0u, ~0u, ~0u, ~0u},
            "Mouse router corrupted a live SSE register");
    if (mode != mouse::Result::passthrough)
        require((registers.flags & 0x41) == 0x41, "Mouse router corrupted live integer flags");
    for (unsigned i = 0; i < frame.bytes.size(); ++i) {
        const auto offset = static_cast<std::ptrdiff_t>(i) - 0x240;
        if (offset != activeOffset && (offset < xOffset || offset >= yOffset + 4))
            require(frame.bytes[i] == 0xa5, "Mouse adapter wrote outside its native locals");
    }
}
void routing() {
    Frame frame;
    frame.active() = false;
    frame.x() = 7;
    frame.y() = 8;
    mode = mouse::Result::passthrough;
    run(frame);
    close(frame.x(), 1.04f, "Passthrough changed native horizontal aim");
    require(frame.active() && nativeCalls == 1 && routed == 1 && mouse_fixture_resumes == 1,
            "Passthrough did not execute the original mouse block once");
    mode = mouse::Result::inactive;
    frame.active() = false;
    frame.x() = 7;
    frame.y() = 8;
    run(frame);
    require(!frame.active() && frame.x() == 7 && frame.y() == 8 && nativeCalls == 1,
            "Inactive network pointer overwrote earlier native input locals");
    mode = mouse::Result::active;
    for (const int h : {540, 1080, 2160}) {
        height = h;
        run(frame);
        close(frame.x(), 12.0f * static_cast<float>(height) / 270.0f * 0.65f * 0.02f,
              "Network world target changed with the receiver's display size");
        close(frame.y(), -8.0f * static_cast<float>(height) / 270.0f * 0.65f * 0.02f,
              "Network vertical world target changed scale");
    }
    height = 1080;
    sampleInsideRouter = true;
    run(frame);
    sampleInsideRouter = false;
    require(nativeCalls == 2 && routed == 6 && mouse_fixture_resumes == 6,
            "A physical bypass reentered routing or the rest of Player::Controls");
    frame.active() = false;
    frame.x() = 7;
    networkAim.x = std::numeric_limits<float>::quiet_NaN();
    run(frame);
    require(!frame.active() && frame.x() == 7, "Nonfinite replay modified native input locals");
    networkAim.x = 2.4f;
}
void physicalQueries() {
    const auto routes = routed, resumes = mouse_fixture_resumes;
    mouse::Vector result;
    for (int h : {540, 1080, 2160}) {
        height = h;
        require(physical(player.data(), &result, false), "Physical mouse input was lost");
        close(result.x, 52.0f * 270.0f / static_cast<float>(height) / 0.65f * 0.2f,
              "Pixel input did not become a canonical world displacement");
    }
    height = 1080;
    nestedCapture = true;
    require(physical(player.data(), &result, false), "Outer physical frame was lost");
    close(result.y, -2.0f, "Nested capture overwrote the outer frame");
    require(routed == routes && mouse_fixture_resumes == resumes,
            "Physical sampling executed the router or following gameplay code");
    mouseDown = false;
    result = {9, 10};
    require(!physical(player.data(), &result, false) && result.x == 9 && result.y == 10,
            "Inactive physical query published undefined output");
    mouseDown = true;
    field<int>(player.data(), 0x154c) = 2;
    require(!physical(player.data(), &result, false) && field<int>(player.data(), 0x154c) == 2,
            "Physical bypass changed native controller ownership");
    field<int>(player.data(), 0x154c) = 0;
    height = 0;
    require(!physical(player.data(), &result, false), "Invalid viewport produced an aim value");
    height = 1080;
    const auto original = physical;
    require(!backend::mouse_input::install(base(), route, physical) && physical == original,
            "Duplicate install replaced the physical bypass");
    require(!physical(nullptr, &result, false) && !physical(player.data(), nullptr, false),
            "Missing borrowed arguments reached native code");
}
} // namespace
int main() {
    setup();
    routing();
    physicalQueries();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release standalone mouse fixture");
}

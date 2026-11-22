#include "test_support.h"
#include "engine/versions/common/scene_update.cpp"
#include <windows.h>
#include <array>
#include <cstring>
#include <vector>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned updateEntry = backend::entry::bossOverlayUpdateBoundary;
#else
#include "engine/versions/j511/entrypoints.h"
namespace backend = isaac::engine::j511;
constexpr unsigned updateEntry = backend::entry::bossOverlayUpdate;
#endif
namespace isaac::runtime {
bool guest = false, terminal = false, disturb = false;
bool replica() {
    if (disturb) {
        unsigned control;
        __asm__ __volatile__("stmxcsr %0" : "=m"(control));
        control ^= 0x6000;
        __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0"
                             :
                             : "m"(control)
                             : "xmm7");
    }
    return guest;
}
bool ending() {
    return terminal;
}
} // namespace isaac::runtime
extern "C" {
void* sceneTarget = nullptr;
unsigned sceneUpdates = 0, sceneSkipped = 0, sceneRegisters[8]{}, sceneFlags = 0;
unsigned sceneStackBefore = 0, sceneStackAfter = 0;
alignas(16) unsigned char sceneFloating[512]{};
__attribute__((naked)) void sceneObserved() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, %esi\n\t"
                         "movl $_sceneRegisters, %edi\n\tmovl $8, %ecx\n\tcld\n\trep movsl\n\t"
                         "movl 32(%esp), %eax\n\tmovl %eax, _sceneFlags\n\t"
                         "fxsave _sceneFloating\n\tpopal\n\tpopfl\n\tret");
}
__attribute__((naked)) void sceneOriginal() {
    __asm__ __volatile__("pushfl\n\tincl _sceneUpdates\n\tpopfl\n\tjmp _sceneObserved");
}
__attribute__((naked)) void sceneSkip() {
    __asm__ __volatile__("pushfl\n\tincl _sceneSkipped\n\tpopfl\n\tjmp _sceneObserved");
}
__attribute__((naked, fastcall)) void invokeScene(void*, void*) {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, _sceneStackBefore\n\t"
                         "movl %ecx, %edi\n\tmovl $0x12345678, %eax\n\t"
                         "movl $0x22334455, %edx\n\tmovl $0x33445566, %ebx\n\t"
                         "movl $0x44556677, %ebp\n\tmovl $0x55667788, %esi\n\t"
                         "pcmpeqd %xmm7, %xmm7\n\tfld1\n\tcmpl %eax, %eax\n\tstc\n\t"
                         "call *_sceneTarget\n\tmovl %esp, _sceneStackAfter\n\t"
                         "movl _sceneStackBefore, %esp\n\tfstp %st(0)\n\tpopal\n\tpopfl\n\tret");
}
}
namespace {
void jump(unsigned char* target, void* function) {
    std::memset(target, 0x90, 16);
    target[0] = 0xe9;
    const auto relative =
        reinterpret_cast<std::uintptr_t>(function) - reinterpret_cast<std::uintptr_t>(target + 5);
    std::memcpy(target + 1, &relative, sizeof(relative));
}
#ifdef ISAAC_LAN_TEST_J835
unsigned word(const unsigned char* memory, unsigned offset) {
    unsigned value;
    std::memcpy(&value, memory + offset, sizeof(value));
    return value;
}
#endif
} // namespace
int main() {
    try {
        namespace scene = isaac::engine::native_scene_update;
        require(!scene::install(0), "Missing native image installed a scene hook");
        constexpr unsigned imageSize = 0x600000;
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate scene fixture");
        auto* target = image + updateEntry;
#ifdef ISAAC_LAN_TEST_J835
        // The actual J835 boundary first reads Game.BossOverlay.state into EAX.
        const unsigned char readState[]{0x8b, 0x87, 0x20, 0xcf, 0x01, 0};
        std::memcpy(target, readState, sizeof(readState));
        jump(target + sizeof(readState), reinterpret_cast<void*>(sceneOriginal));
        jump(image + backend::entry::bossOverlayUpdateSkip, reinterpret_cast<void*>(sceneSkip));
#else
        jump(target, reinterpret_cast<void*>(sceneOriginal));
#endif
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        const auto base = reinterpret_cast<std::uintptr_t>(image);
        require(MH_CreateHook(target, reinterpret_cast<void*>(sceneOriginal), nullptr) == MH_OK,
                "Prepare scene hook conflict");
        require(!scene::install(base) && !isaac_lan_scene_update_original &&
                    !isaac_lan_scene_update_skip,
                "Scene conflict retained a borrowed continuation");
        require(MH_CreateHook(target, reinterpret_cast<void*>(sceneOriginal), nullptr) ==
                    MH_ERROR_ALREADY_CREATED,
                "Scene conflict cleanup removed a foreign hook");
        require(MH_RemoveHook(target) == MH_OK && scene::install(base) && !scene::install(base),
                "Scene retry or duplicate install corrupted its trampoline");
        sceneTarget = target;
        std::vector<unsigned char> object(0x1cf40, 0xa5);
        const unsigned mode = 1;
        std::memcpy(object.data() + 0x1cf20, &mode, sizeof(mode));
        const auto before = object;
        const auto receiver = reinterpret_cast<std::uintptr_t>(object.data());
        unsigned control;
        __asm__ __volatile__("stmxcsr %0" : "=m"(control));
        for (bool guest : {false, true, true, false})
            for (bool terminal : {false, true, false}) {
                isaac::runtime::guest = guest;
                isaac::runtime::terminal = terminal;
#ifdef ISAAC_LAN_TEST_J835
                isaac::runtime::disturb = true;
#endif
                sceneUpdates = sceneSkipped = 0;
                invokeScene(object.data(), nullptr);
                const bool advance = !guest || terminal;
                require(sceneUpdates == static_cast<unsigned>(advance) &&
                            sceneStackBefore == sceneStackAfter && object == before,
                        "Scene hook advanced the wrong peer, changed native data or unbalanced the "
                        "stack");
#ifdef ISAAC_LAN_TEST_J835
                require(sceneSkipped == static_cast<unsigned>(!advance),
                        "Inlined scene suppression missed the next native update block");
                const std::array<unsigned, 8> expected{
                    receiver,   0x55667788, 0x44556677, 0,
                    0x33445566, 0x22334455, receiver,   advance ? mode : 0x12345678};
                for (unsigned i = 0; i < expected.size(); ++i)
                    if (i != 3)
                        require(sceneRegisters[i] == expected[i],
                                "Inlined scene boundary lost a live native register");
                require((sceneFlags & 0x41) == 0x41 && word(sceneFloating, 24) == control &&
                            word(sceneFloating, 160 + 7 * 16) == 0xffffffff &&
                            sceneFloating[4] == 0x80 && word(sceneFloating, 32) == 0 &&
                            word(sceneFloating, 36) == 0x80000000 && sceneFloating[40] == 0xff &&
                            sceneFloating[41] == 0x3f,
                        "Scene decision corrupted live flags, SSE, x87 or floating-point controls");
#else
                require(!sceneSkipped && (!advance || sceneRegisters[6] == receiver),
                        "Standalone scene method changed its thiscall receiver");
#endif
            }
        require(MH_Uninitialize() == MH_OK, "Remove scene fixture hook");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS standalone and inline native scene suppression, ABI and hook ownership");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

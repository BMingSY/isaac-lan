// Execute the production boundary thunks and real MinHook trampolines without
// loading the game. Native layout expectations remain independent of bindings.
#include "test_support.h"
#include "engine/versions/common/challenge_hud.cpp"
#include <windows.h>
#include <cstring>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned presenceRegister = 5, parameterRegister = 6, noUnlocksDistance = 0x99;
constexpr unsigned parameterBoundary = backend::entry::hUDChallengeParamsRead;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
constexpr unsigned presenceRegister = 6, parameterRegister = 7, noUnlocksDistance = 0xa2;
constexpr unsigned parameterBoundary = backend::entry::hUDChallengeParamsReturn;
#endif
namespace isaac::runtime {
std::array<int, 2> goal{-1, -1};
bool disturbFloatingPoint;
std::array<int, 2> challengeDestination() {
    if (disturbFloatingPoint) {
        unsigned control;
        __asm__ __volatile__("stmxcsr %0" : "=m"(control));
        control ^= 0x6000;
        __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0"
                             :
                             : "m"(control)
                             : "xmm7");
    }
    return goal;
}
} // namespace isaac::runtime
extern "C" {
unsigned destinationCalls = 0, observedFlags = 0, observedRegisters[8]{};
alignas(16) unsigned char observedFloating[512]{};
void* destinationTarget = nullptr;
__attribute__((naked)) void destinationFixture() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, %esi\n\t"
                         "movl $_observedRegisters, %edi\n\tmovl $8, %ecx\n\tcld\n\trep movsl\n\t"
                         "movl 32(%esp), %eax\n\tmovl %eax, _observedFlags\n\t"
                         "incl _destinationCalls\n\tfxsave _observedFloating\n\t"
                         "popal\n\tpopfl\n\tret");
}
__attribute__((naked, fastcall)) void invokeDestination(void*, void*) {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %ecx, %ebp\n\tmovl %edx, %ecx\n\t"
                         "movl %edx, %eax\n\tmovl $0xaabbcc00, %edx\n\t"
                         "movl $0x12345678, %ebx\n\tmovl $0x22334455, %esi\n\t"
                         "movl $0x66778899, %edi\n\tpcmpeqd %xmm7, %xmm7\n\tfld1\n\t"
                         "cmpl %eax, %eax\n\tstc\n\tcall *_destinationTarget\n\t"
                         "fstp %st(0)\n\tpopal\n\tpopfl\n\tret");
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
unsigned word(const unsigned char* data, unsigned offset) {
    unsigned result;
    std::memcpy(&result, data + offset, sizeof(result));
    return result;
}
void checkParameters(const void* pointer, std::array<int, 2> goal) {
    std::array<unsigned char, 0xa4> expected{};
    std::memcpy(expected.data() + 0x40, &goal[0], sizeof(int));
#ifdef ISAAC_LAN_TEST_J835
    expected[0x6d] = goal[1] == 1;
    expected[0x88] = goal[1] == 2;
#else
    std::memcpy(expected.data() + 0x80, &goal[1], sizeof(int));
#endif
    require(std::memcmp(pointer, expected.data(), expected.size()) == 0,
            "HUD parameters have wrong destination fields or contain native owned data");
}
} // namespace
int main() {
    try {
        using namespace isaac::presentation;
        require(!installChallengeHud(0), "A missing image installed HUD hooks");
        isaac_lan_destination_original = isaac_lan_destination_params_original =
            reinterpret_cast<void*>(destinationFixture);
        std::array<std::uint8_t, 256> frame{};
        auto* ebp = frame.data() + 200;
        std::array<unsigned char, 0xa4> nativeParameters;
        nativeParameters.fill(0x7a);
        const auto nativeBefore = nativeParameters;
        const auto nativePointer = reinterpret_cast<std::uintptr_t>(nativeParameters.data());
        unsigned control;
        __asm__ __volatile__("stmxcsr %0" : "=m"(control));
        isaac::runtime::disturbFloatingPoint = true;
        for (const auto goal :
             {std::array{-1, -1}, std::array{11, 0}, std::array{6, 0}, std::array{10, 1},
              std::array{8, 2}, std::array{11, 0}, std::array{-1, -1}}) {
            isaac::runtime::goal = goal;
            const bool active = goal[0] >= 0;
            for (bool parameters : {false, true}) {
                frame.fill(0x7a);
                const auto before = frame;
                destinationCalls = 0;
                destinationTarget = reinterpret_cast<void*>(
                    parameters ? isaac_lan_destination_params_thunk : isaac_lan_destination_thunk);
                invokeDestination(ebp, nativeParameters.data());
                require(destinationCalls == 1, "A boundary skipped or repeated the native draw");
                std::array<unsigned, 8> expected{0x66778899,
                                                 0x22334455,
                                                 reinterpret_cast<std::uintptr_t>(ebp),
                                                 0,
                                                 0x12345678,
                                                 0xaabbcc00,
                                                 nativePointer,
                                                 nativePointer};
                if (active) {
                    if (parameters) {
                        expected[parameterRegister] = observedRegisters[parameterRegister];
                        require(expected[parameterRegister] != nativePointer,
                                "Destination view did not replace the native parameter pointer");
                        checkParameters(reinterpret_cast<void*>(expected[parameterRegister]), goal);
                    } else
                        expected[presenceRegister] = (expected[presenceRegister] & ~0xffu) | 1u;
                }
                for (unsigned i = 0; i < expected.size(); ++i)
                    if (i != 3)
                        require(observedRegisters[i] == expected[i],
                                "HUD boundary modified an unrelated live register");
                require((observedFlags & 0x41) == 0x41 && word(observedFloating, 24) == control &&
                            word(observedFloating, 160 + 7 * 16) == 0xffffffff,
                        "HUD boundary corrupted flags, SSE or floating-point controls");
                // FXSAVE's first x87 value is 80-bit 1.0, with one occupied register.
                require(observedFloating[4] == 0x80 && word(observedFloating, 32) == 0 &&
                            word(observedFloating, 36) == 0x80000000 &&
                            observedFloating[40] == 0xff && observedFloating[41] == 0x3f,
                        "HUD boundary lost the caller's live x87 stack");
                for (unsigned i = 0; i < frame.size(); ++i)
                    require(
                        frame[i] ==
                            (active && !parameters && i == 200 - noUnlocksDistance ? 1 : before[i]),
                        "Destination detour touched unrelated HUD frame data");
                require(nativeParameters == nativeBefore,
                        "A visual destination modified the original challenge object");
            }
        }
        isaac::runtime::disturbFloatingPoint = false;
        constexpr unsigned imageSize = 0x600000;
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate native HUD fixture");
        auto* destination = image + backend::entry::hUDChallengeDestination;
        auto* parameters = image + parameterBoundary;
        jump(destination, reinterpret_cast<void*>(destinationFixture));
        // Match the real boundary's CMP + short JE. Exercise MinHook's relocated
        // branch both ways; the original Game/DailyChallenge view stays borrowed.
        parameters[0] = 0x80;
#ifdef ISAAC_LAN_TEST_J835
        parameters[1] = 0x79; // [ECX+0x74]
#else
        parameters[1] = 0x78; // [EAX+0x74]
#endif
        parameters[2] = 0x74;
        parameters[3] = 0;
        parameters[4] = 0x74;
        parameters[5] = 5;
        jump(parameters + 6, reinterpret_cast<void*>(destinationFixture));
        jump(parameters + 11, reinterpret_cast<void*>(destinationFixture));
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        const auto imageAddress = reinterpret_cast<std::uintptr_t>(image);
        for (auto* conflict : {destination, parameters}) {
            require(MH_CreateHook(conflict, reinterpret_cast<void*>(destinationFixture), nullptr) ==
                        MH_OK,
                    "Prepare HUD hook conflict");
            require(!installChallengeHud(imageAddress) && !isaac_lan_destination_original &&
                        !isaac_lan_destination_params_original,
                    "Failed HUD installation retained partial state");
            require(MH_CreateHook(conflict, reinterpret_cast<void*>(destinationFixture), nullptr) ==
                        MH_ERROR_ALREADY_CREATED,
                    "HUD rollback removed a foreign hook");
            auto* other = conflict == destination ? parameters : destination;
            require(MH_CreateHook(other, reinterpret_cast<void*>(destinationFixture), nullptr) ==
                        MH_OK,
                    "HUD rollback leaked one of its own hooks");
            require(MH_RemoveHook(other) == MH_OK && MH_RemoveHook(conflict) == MH_OK,
                    "Clean fixture hooks");
        }
        require(installChallengeHud(imageAddress) && !installChallengeHud(imageAddress),
                "HUD retry failed or duplicate install overwrote its trampolines");
        destinationTarget = parameters;
        for (bool active : {false, true, false}) {
            isaac::runtime::goal = active ? std::array{11, 0} : std::array{-1, -1};
            destinationCalls = 0;
            invokeDestination(ebp, nativeParameters.data());
            require(destinationCalls == 1, "Relocated HUD branch missed native continuation");
            const auto pointer = observedRegisters[parameterRegister];
            if (active)
                checkParameters(reinterpret_cast<void*>(pointer), {11, 0});
            else
                require(pointer == nativePointer,
                        "Leaving LAN replaced ordinary challenge parameters");
            require(((observedFlags & 0x40) != 0) == active,
                    "Relocated parameter read consumed the wrong view");
        }
        require(nativeParameters == nativeBefore, "Hooked HUD draw modified native parameters");
        require(MH_Uninitialize() == MH_OK, "Remove HUD fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts(
            "PASS destination HUD boundaries, native layouts, register state and hook cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

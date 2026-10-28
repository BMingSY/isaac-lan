#include "engine/challenge_hud.h"
#include "engine/versions/common/challenge_hud_bindings.h"
#include "runtime/session.h"
#include <MinHook.h>

namespace isaac::presentation {
namespace {
using engine::native_challenge_hud::bindings;
bool installed;
engine::native_challenge_hud::Parameters destinationParams{};
} // namespace
extern "C" {
void* isaac_lan_destination_original = nullptr;
void* isaac_lan_destination_params_original = nullptr;
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_destination_prepare(
    std::uint32_t* registers) {
    if (runtime::challengeDestination()[0] < 0)
        return;
    auto& presence = registers[bindings.presenceRegister];
    presence = (presence & ~0xffu) | 1u;
    *reinterpret_cast<std::uint8_t*>(registers[engine::native_challenge_hud::ebp] +
                                     bindings.noUnlocks) = 1;
}
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_destination_params_prepare(
    std::uint32_t* registers) {
    const auto goal = runtime::challengeDestination();
    if (goal[0] < 0)
        return;
    destinationParams.fill(0);
    bindings.writeParameters(destinationParams, goal);
    registers[bindings.parametersRegister] =
        reinterpret_cast<std::uintptr_t>(destinationParams.data());
}
// These are HUD instruction boundaries, not native function entrypoints.
// Preserve flags, GPRs, SSE, x87 and their control state; modify only the saved
// destination register or borrowed parameter pointer. The native HUD owns all
// drawing and destroys none of the scalar view's fields.
#define DESTINATION_BOUNDARY(PREPARE, ORIGINAL)                                                    \
    "pushfl\n\tpushal\n\tmovl %esp, %eax\n\t"                                                      \
    "subl $528, %esp\n\tandl $-16, %esp\n\tfxsave (%esp)\n\t"                                      \
    "movl %eax, 512(%esp)\n\tpushl %eax\n\tcall _" #PREPARE "\n\taddl $4, %esp\n\t"                \
    "fxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\tjmp *_" #ORIGINAL
__attribute__((naked)) void isaac_lan_destination_thunk() {
    __asm__ __volatile__(
        DESTINATION_BOUNDARY(isaac_lan_destination_prepare, isaac_lan_destination_original));
}
__attribute__((naked)) void isaac_lan_destination_params_thunk() {
    __asm__ __volatile__(DESTINATION_BOUNDARY(isaac_lan_destination_params_prepare,
                                              isaac_lan_destination_params_original));
}
#undef DESTINATION_BOUNDARY
} // extern "C"
bool installChallengeHud(std::uintptr_t image) {
    if (!image || installed)
        return false;
    std::array<void*, 2> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned rva, auto detour, void*& original) {
        auto* target = reinterpret_cast<void*>(image + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(detour), &original) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success =
        hook(bindings.destination, isaac_lan_destination_thunk, isaac_lan_destination_original) &&
        hook(bindings.parameters, isaac_lan_destination_params_thunk,
             isaac_lan_destination_params_original);
    if (success) {
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
        if (success)
            success = MH_ApplyQueued() == MH_OK;
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        isaac_lan_destination_original = isaac_lan_destination_params_original = nullptr;
    }
    installed = success;
    return success;
}
} // namespace isaac::presentation

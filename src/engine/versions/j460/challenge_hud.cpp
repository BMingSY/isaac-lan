#include "engine/challenge_hud.h"
#include "engine/versions/j460/entrypoints.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <array>

namespace isaac::presentation {
namespace {
std::uintptr_t base = 0;
using Params = const void*(__attribute__((thiscall)) *)(void*);
Params originalParams;
// Only HUD::Render reads this borrowed, scalar-only view. It never escapes to
// native gameplay or destruction; no std::string/vector ownership is copied.
std::array<std::uint32_t, 0xa4 / 4> destinationParams{};
const void* paramsForCaller(void* game, std::uintptr_t caller) {
    const auto goal = runtime::challengeDestination();
    if (goal[0] >= 0 && caller == base + engine::j460::entry::hUDChallengeParamsReturn) {
        destinationParams[0x40 / 4] = goal[0];
        destinationParams[0x80 / 4] = goal[1];
        return destinationParams.data();
    }
    return originalParams(game);
}
const void* __attribute__((fastcall)) params(void* game, void*) {
    return paramsForCaller(game, reinterpret_cast<std::uintptr_t>(__builtin_return_address(0)));
}
} // namespace
extern "C" {
void* isaac_lan_destination_original = nullptr;
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_destination_prepare(
    std::uint32_t* registers) {
    if (runtime::challengeDestination()[0] < 0)
        return;
    // pushad: EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX. HUD::Render consumes CL
    // as its destination-present flag and [EBP-0xa2] as its no-unlocks flag.
    registers[6] = (registers[6] & ~0xffu) | 1u;
    *reinterpret_cast<std::uint8_t*>(registers[2] - 0xa2) = 1;
}
__attribute__((naked)) void isaac_lan_destination_thunk() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tsubl $128, %esp\n\t"
                         "movups %xmm0, 0(%esp)\n\t"
                         "movups %xmm1, 16(%esp)\n\t"
                         "movups %xmm2, 32(%esp)\n\t"
                         "movups %xmm3, 48(%esp)\n\t"
                         "movups %xmm4, 64(%esp)\n\t"
                         "movups %xmm5, 80(%esp)\n\t"
                         "movups %xmm6, 96(%esp)\n\t"
                         "movups %xmm7, 112(%esp)\n\t"
                         "leal 128(%esp), %eax\n\tpushl %eax\n\t"
                         "call _isaac_lan_destination_prepare\n\taddl $4, %esp\n\t"
                         "movups 0(%esp), %xmm0\n\t"
                         "movups 16(%esp), %xmm1\n\t"
                         "movups 32(%esp), %xmm2\n\t"
                         "movups 48(%esp), %xmm3\n\t"
                         "movups 64(%esp), %xmm4\n\t"
                         "movups 80(%esp), %xmm5\n\t"
                         "movups 96(%esp), %xmm6\n\t"
                         "movups 112(%esp), %xmm7\n\t"
                         "addl $128, %esp\n\tpopal\n\tpopfl\n\t"
                         "jmp *_isaac_lan_destination_original");
}
}
bool installChallengeHud(std::uintptr_t image) {
    base = image;
    auto hook = [image](unsigned rva, void* detour, void** original) {
        auto target = reinterpret_cast<void*>(image + rva);
        return MH_CreateHook(target, detour, original) == MH_OK && MH_EnableHook(target) == MH_OK;
    };
    return hook(engine::j460::entry::hUDChallengeDestination,
                reinterpret_cast<void*>(isaac_lan_destination_thunk),
                &isaac_lan_destination_original) &&
           hook(engine::j460::entry::gameGetChallengeParams, reinterpret_cast<void*>(params),
                reinterpret_cast<void**>(&originalParams));
}
} // namespace isaac::presentation

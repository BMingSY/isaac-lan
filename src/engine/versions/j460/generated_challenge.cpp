#include "engine/generated_challenge.h"
#include "engine/versions/j460/branch_hook.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <MinHook.h>
#include <array>

namespace isaac::engine {
namespace {
std::uintptr_t generatedChallengeImage;
bool (*useGeneratedChallenge)() = nullptr;
constexpr unsigned nativeGeneratedChallenge = 45, compareBytes = 7;
using ChestEnding = int(__stdcall*)(bool);
ChestEnding originalChestEnding;
int __stdcall generatedChestEnding(bool alternate) {
    GeneratedChallengeRewardScope scope;
    return originalChestEnding(alternate);
}
void* styleOriginals[5]{};
} // namespace

GeneratedChallengeRewardScope::GeneratedChallengeRewardScope() {
    if (!useGeneratedChallenge || !useGeneratedChallenge())
        return;
    const auto game =
        *reinterpret_cast<std::uintptr_t*>(generatedChallengeImage + j460::globals::game);
    if (!game)
        return;
    challenge = reinterpret_cast<unsigned*>(game + j460::layout::game::challenge);
    previous = *challenge;
    *challenge = nativeGeneratedChallenge;
}
GeneratedChallengeRewardScope::~GeneratedChallengeRewardScope() {
    if (!challenge)
        return;
    const auto game =
        *reinterpret_cast<std::uintptr_t*>(generatedChallengeImage + j460::globals::game);
    if (game && reinterpret_cast<unsigned*>(game + j460::layout::game::challenge) == challenge)
        *challenge = previous;
}

extern "C" {
void* isaac_lan_glitched_grid_return = nullptr;
void* isaac_lan_glitched_rock_return = nullptr;
void* isaac_lan_glitched_backdrop_type_return = nullptr;
void* isaac_lan_glitched_backdrop_return = nullptr;
void* isaac_lan_glitched_room_config_return = nullptr;
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_glitched_prepare(
    std::uint32_t* registers) {
    if (useGeneratedChallenge && useGeneratedChallenge())
        j460::branch::selectEqual(registers);
}
#define ISAAC_LAN_GLITCHED_THUNK(name, gameRegister)                                               \
    __attribute__((naked)) void name() {                                                           \
        __asm__ __volatile__(                                                                      \
            "cmpl $%c[challenge], %c[offset](%%" #gameRegister                                     \
            ")\n\t" ISAAC_LAN_BRANCH_CALL(isaac_lan_glitched_prepare) "jmp *_" #name "_return"     \
            :                                                                                      \
            : [challenge] "i"(nativeGeneratedChallenge), [offset] "i"(                             \
                                                             j460::layout::game::challenge));      \
    }
ISAAC_LAN_GLITCHED_THUNK(isaac_lan_glitched_grid, edx)
ISAAC_LAN_GLITCHED_THUNK(isaac_lan_glitched_rock, edx)
ISAAC_LAN_GLITCHED_THUNK(isaac_lan_glitched_backdrop_type, edi)
ISAAC_LAN_GLITCHED_THUNK(isaac_lan_glitched_backdrop, edx)
ISAAC_LAN_GLITCHED_THUNK(isaac_lan_glitched_room_config, edi)
#undef ISAAC_LAN_GLITCHED_THUNK
}

bool installGeneratedChallenge(std::uintptr_t image, bool (*enabled)()) {
    generatedChallengeImage = image;
    useGeneratedChallenge = enabled;
    struct Site {
        unsigned entry;
        void (*detour)();
        void** continuation;
    };
    const std::array sites{
        Site{j460::entry::glitchedGridStyle, isaac_lan_glitched_grid,
             &isaac_lan_glitched_grid_return},
        Site{j460::entry::glitchedRockStyle, isaac_lan_glitched_rock,
             &isaac_lan_glitched_rock_return},
        Site{j460::entry::glitchedBackdropType, isaac_lan_glitched_backdrop_type,
             &isaac_lan_glitched_backdrop_type_return},
        Site{j460::entry::glitchedBackdropStyle, isaac_lan_glitched_backdrop,
             &isaac_lan_glitched_backdrop_return},
        Site{j460::entry::glitchedRoomConfig, isaac_lan_glitched_room_config,
             &isaac_lan_glitched_room_config_return},
    };
    for (unsigned i = 0; i < sites.size(); ++i) {
        const auto& site = sites[i];
        auto target = reinterpret_cast<void*>(image + site.entry);
        *site.continuation = reinterpret_cast<void*>(image + site.entry + compareBytes);
        if (MH_CreateHook(target, reinterpret_cast<void*>(site.detour), &styleOriginals[i]) !=
                MH_OK ||
            MH_EnableHook(target) != MH_OK)
            return false;
    }
    auto target = reinterpret_cast<void*>(image + j460::entry::gameGetChestEnding);
    return MH_CreateHook(target, reinterpret_cast<void*>(generatedChestEnding),
                         reinterpret_cast<void**>(&originalChestEnding)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
} // namespace isaac::engine

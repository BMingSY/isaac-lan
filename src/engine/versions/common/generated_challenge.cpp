#include "engine/generated_challenge.h"
#include "engine/versions/common/branch_frame.h"
#include "engine/versions/common/generated_challenge_bindings.h"
#include "engine/versions/common/hooks.h"
#include "runtime/session.h"

namespace isaac::engine {
namespace {
using native_generated_challenge::bindings;
std::uintptr_t generatedChallengeImage;
bool (*useGlitchedStyle)() = nullptr;
unsigned (*selectedRewardChallenge)() = nullptr;
constexpr unsigned compareBytes = 7;
constexpr unsigned arithmeticFlags = 0x8d5, equalFlags = 0x44;
using ChestEnding = int(__stdcall*)(bool);
ChestEnding originalChestEnding;
int __stdcall generatedChestEnding(bool alternate) {
    ChallengeRewardScope scope;
    return originalChestEnding(alternate);
}
std::array<void*, 5> styleOriginals{};
} // namespace

ChallengeRewardScope::ChallengeRewardScope() {
    const auto selected = selectedRewardChallenge ? selectedRewardChallenge() : 0;
    if (!selected)
        return;
    const auto game = *reinterpret_cast<std::uintptr_t*>(generatedChallengeImage + bindings.game);
    if (!game)
        return;
    challenge = reinterpret_cast<unsigned*>(game + bindings.challenge);
    previous = *challenge;
    *challenge = selected;
}
ChallengeRewardScope::~ChallengeRewardScope() {
    if (!challenge)
        return;
    const auto game = *reinterpret_cast<std::uintptr_t*>(generatedChallengeImage + bindings.game);
    if (game && reinterpret_cast<unsigned*>(game + bindings.challenge) == challenge)
        *challenge = previous;
}

extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_style_prepare(
    native_branch::Frame* frame, unsigned index) noexcept {
    (*frame)[native_branch::continuation] = reinterpret_cast<std::uintptr_t>(styleOriginals[index]);
    try {
        if (useGlitchedStyle && useGlitchedStyle())
            (*frame)[native_branch::flags] =
                ((*frame)[native_branch::flags] & ~arithmeticFlags) | equalFlags;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
    } catch (...) {
        runtime::abort("Native generated challenge callback failed");
    }
}
#define STYLE_BOUNDARY(NAME, INDEX)                                                                \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__(                                                                      \
            ISAAC_LAN_NATIVE_BRANCH_SAVE                                                           \
            "pushl $" #INDEX "\n\tpushl %eax\n\t"                                                  \
            "call _isaac_lan_style_prepare\n\taddl $8, %esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE); \
    }
STYLE_BOUNDARY(isaac_lan_glitched_grid, 0)
STYLE_BOUNDARY(isaac_lan_glitched_rock, 1)
STYLE_BOUNDARY(isaac_lan_glitched_backdrop_type, 2)
STYLE_BOUNDARY(isaac_lan_glitched_backdrop, 3)
STYLE_BOUNDARY(isaac_lan_glitched_room_config, 4)
#undef STYLE_BOUNDARY
}

bool installGeneratedChallenge(std::uintptr_t image, bool (*style)(),
                               unsigned (*rewardChallenge)()) {
    if (generatedChallengeImage)
        return generatedChallengeImage == image && useGlitchedStyle == style &&
               selectedRewardChallenge == rewardChallenge;
    if (!image)
        return false;
    const std::array replacements{isaac_lan_glitched_grid, isaac_lan_glitched_rock,
                                  isaac_lan_glitched_backdrop_type, isaac_lan_glitched_backdrop,
                                  isaac_lan_glitched_room_config};
    native_hooks::Group<6> hooks;
    for (unsigned i = 0; i < replacements.size(); ++i)
        if (!hooks.add(image + bindings.styles[i] + compareBytes, replacements[i],
                       styleOriginals[i]))
            return false;
    if (!hooks.add(image + bindings.chestEnding, generatedChestEnding, originalChestEnding))
        return false;
    generatedChallengeImage = image;
    useGlitchedStyle = style;
    selectedRewardChallenge = rewardChallenge;
    if (!hooks.enable()) {
        generatedChallengeImage = 0;
        useGlitchedStyle = nullptr;
        selectedRewardChallenge = nullptr;
        return false;
    }
    return true;
}
} // namespace isaac::engine

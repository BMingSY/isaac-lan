// Run production hooks against native-call fixtures, without loading the game.
#include "test_support.h"
#include "engine/versions/common/victory_prompt.cpp"
#include <windows.h>
#include <algorithm>
#include <utility>
#include <vector>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned promptOffset = 0x1c33fc, selectionOffset = 0x80218, resultOffset = 0x8021c;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
constexpr unsigned promptOffset = 0x26c18, selectionOffset = 0x128, resultOffset = 0x12c;
#endif
namespace isaac::runtime {
int slot = -1;
bool guest = false, challenge = false;
int localViewSlot() {
    return slot;
}
bool replica() {
    return guest;
}
bool challengeActive() {
    return challenge;
}
} // namespace isaac::runtime
namespace isaac::input {
std::array<bool, 24> edges{};
unsigned queries = 0;
bool hostMenuTriggered(int action) {
    require(action == 20 || action == 21 || action == 14, "Prompt queried a non-menu action");
    ++queries;
    return std::exchange(edges.at(action), false);
}
} // namespace isaac::input
extern "C" {
void* promptTarget = nullptr;
unsigned promptStackBefore = 0, promptStackAfter = 0, promptSaved[4]{};
__attribute__((naked, fastcall)) void invokePrompt(void*, void*) {
    __asm__ __volatile__("pushal\n\tmovl %esp, _promptStackBefore\n\t"
                         "movl $0x11223344, %ebx\n\tmovl $0x22334455, %esi\n\t"
                         "movl $0x33445566, %edi\n\tmovl $0x44556677, %ebp\n\t"
                         "call *_promptTarget\n\tmovl %esp, _promptStackAfter\n\t"
                         "movl %ebx, _promptSaved\n\tmovl %esi, _promptSaved+4\n\t"
                         "movl %edi, _promptSaved+8\n\tmovl %ebp, _promptSaved+12\n\t"
                         "movl _promptStackBefore, %esp\n\tpopal\n\tret");
}
}
namespace {
using Address = std::uintptr_t;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
unsigned nativeControls = 0, nativeRenders = 0, nativeHides = 0;
void* observed = nullptr;
std::array<unsigned char, 0x40> animation{}, disappearing{};
void __attribute__((fastcall)) controlFixture(void* object, void*) {
    ++nativeControls;
    observed = object;
}
void __attribute__((fastcall)) renderFixture(void* object, void*) {
    ++nativeRenders;
    observed = object;
}
void __attribute__((fastcall)) hideFixture(void* object, void*) {
    ++nativeHides;
    observed = object;
    field<Address>(object, 0x34) = reinterpret_cast<Address>(disappearing.data());
}
void jump(unsigned char* target, void* function) {
    std::memset(target, 0x90, 16);
    target[0] = 0xe9;
    const auto relative =
        reinterpret_cast<Address>(function) - reinterpret_cast<Address>(target + 5);
    std::memcpy(target + 1, &relative, sizeof(relative));
}
void call(void* target, void* object) {
    promptTarget = target;
    invokePrompt(object, nullptr);
    constexpr std::array expected{0x11223344u, 0x22334455u, 0x33445566u, 0x44556677u};
    require(promptStackBefore == promptStackAfter &&
                std::equal(expected.begin(), expected.end(), promptSaved),
            "Prompt hook corrupted the thiscall stack or callee-saved registers");
}
void expectState(bool open, int selection, int result, bool vote, bool idle) {
    const auto state = isaac::engine::native_victory_prompt::read();
    require(state.open == open && state.selection == selection && state.result == result &&
                state.nativeVote == vote && state.idle == idle,
            "Prompt snapshot differs from native state");
}
} // namespace
int main() {
    try {
        namespace prompt = isaac::engine::native_victory_prompt;
        namespace runtime = isaac::runtime;
        namespace input = isaac::input;
        expectState(false, -1, 0, false, false);
        require(!prompt::install(0), "Missing image installed prompt hooks");
        constexpr unsigned imageSize = 0x900000;
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate prompt fixture");
        auto* controls = image + backend::entry::victoryPromptControls;
        auto* render = image + backend::entry::victoryPromptRender;
        jump(controls, reinterpret_cast<void*>(controlFixture));
        jump(render, reinterpret_cast<void*>(renderFixture));
        jump(image + backend::entry::victoryPromptHide, reinterpret_cast<void*>(hideFixture));
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        const auto base = reinterpret_cast<Address>(image);
        for (auto* conflict : {controls, render}) {
            require(MH_CreateHook(conflict, reinterpret_cast<void*>(controlFixture), nullptr) ==
                        MH_OK,
                    "Prepare prompt hook conflict");
            require(!prompt::install(base) && !prompt::image && !prompt::originalControls &&
                        !prompt::originalRender,
                    "Failed prompt installation retained borrowed state");
            require(MH_CreateHook(conflict, reinterpret_cast<void*>(controlFixture), nullptr) ==
                        MH_ERROR_ALREADY_CREATED,
                    "Prompt rollback removed a foreign hook");
            auto* other = conflict == controls ? render : controls;
            require(MH_CreateHook(other, reinterpret_cast<void*>(controlFixture), nullptr) == MH_OK,
                    "Prompt rollback leaked an owned hook");
            require(MH_RemoveHook(other) == MH_OK && MH_RemoveHook(conflict) == MH_OK,
                    "Clear prompt fixture hooks");
        }
        require(prompt::install(base) && !prompt::install(base),
                "Prompt retry failed or duplicate install replaced its trampolines");
        std::vector<unsigned char> game(promptOffset + resultOffset + 32, 0xa5);
        std::vector<unsigned char> unrelated(resultOffset + 32, 0xa5);
        auto* object = game.data() + promptOffset;
        field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
        auto reset = [&](int slot = 0, bool challenge = false) {
            runtime::slot = slot;
            runtime::guest = slot > 0;
            runtime::challenge = challenge;
            nativeControls = nativeRenders = nativeHides = input::queries = 0;
            observed = nullptr;
            input::edges.fill(false);
            std::fill(game.begin(), game.end(), 0xa5);
            animation.fill(0);
            disappearing.fill(0);
            std::memcpy(animation.data(), "Idle", 4);
            field<unsigned>(animation.data(), 0x10) = 4;
            field<unsigned>(animation.data(), 0x14) = 15;
            std::memcpy(disappearing.data(), "Dissappear", 10);
            field<unsigned>(disappearing.data(), 0x10) = 10;
            field<unsigned>(disappearing.data(), 0x14) = 15;
            field<Address>(object, 0x34) = reinterpret_cast<Address>(animation.data());
            field<bool>(object, 0x44) = true;
            field<int>(object, selectionOffset) = 0;
            field<int>(object, resultOffset) = 0;
#ifndef ISAAC_LAN_TEST_J835
            field<bool>(object, 0x130) = true;
#endif
        };
        // Ordinary play and other native prompts must keep their original callbacks.
        for (bool same : {false, true}) {
            reset(same ? -1 : 0);
            auto* receiver = same ? object : unrelated.data();
            const auto before = game, otherBefore = unrelated;
            call(controls, receiver);
            call(render, receiver);
            require(nativeControls == 1 && nativeRenders == 1 && observed == receiver &&
                        !nativeHides && !input::queries && game == before &&
                        unrelated == otherBefore,
                    "Unrelated or single-player prompt was intercepted");
        }
        for (int slot : {1, 2, 3}) {
            reset(slot);
            input::edges[14] = input::edges[20] = true;
            const auto before = game;
            call(controls, object);
            call(render, object);
            require(!nativeControls && !nativeRenders && !nativeHides && !input::queries &&
                        game == before,
                    "A guest consumed input, rendered, voted or altered the prompt");
        }
        for (int selection : {0, 1}) {
            reset();
            field<int>(object, selectionOffset) = selection;
            auto expected = game;
            auto* expectedPrompt = expected.data() + promptOffset;
#ifndef ISAAC_LAN_TEST_J835
            field<bool>(expectedPrompt, 0x130) = false;
            expectState(true, selection, 0, true, true);
#else
            expectState(true, selection, 0, false, true);
#endif
            input::edges[14] = true;
            call(controls, object);
            field<int>(expectedPrompt, resultOffset) = selection ? 1 : 2;
            field<Address>(expectedPrompt, 0x34) = reinterpret_cast<Address>(disappearing.data());
            require(nativeHides == 1 && observed == object && !nativeControls && game == expected,
                    "Host confirmation wrote the wrong result, receiver or adjacent data");
            expectState(true, selection, selection ? 1 : 2, false, false);
            call(controls, object);
            input::edges[14] = true;
            call(controls, object);
            call(render, object);
            require(nativeHides == 1 && nativeRenders == 1 && game == expected,
                    "Consumed confirmation repeated a decision during the hide animation");
        }
        reset();
        auto expected = game;
#ifndef ISAAC_LAN_TEST_J835
        field<bool>(expected.data() + promptOffset, 0x130) = false;
#endif
        for (int direction : {20, 21, 21, 20}) {
            input::edges[direction] = true;
            call(controls, object);
            auto& selected = field<int>(expected.data() + promptOffset, selectionOffset);
            selected = 1 - selected;
            require(game == expected && !nativeHides,
                    "Host navigation changed unrelated prompt data");
            call(controls, object);
            require(game == expected, "A consumed navigation edge repeated at simulation rate");
        }
        // Inline and heap strings are borrowed; active non-Idle phases cannot confirm.
        char heapName[] = "Idle";
        for (int phase : {0, 1, 2, 3, 4, 5}) {
            reset();
            if (phase == 0) {
                field<Address>(animation.data(), 0) = reinterpret_cast<Address>(heapName);
                field<unsigned>(animation.data(), 0x14) = 31;
            } else if (phase == 1)
                field<Address>(object, 0x34) = 0;
            else if (phase == 2)
                field<bool>(object, 0x44) = false;
            else if (phase == 3)
                animation[0] = 'X';
            else if (phase == 4)
                field<unsigned>(animation.data(), 0x10) = 5;
            else {
                field<Address>(animation.data(), 0) = 0;
                field<unsigned>(animation.data(), 0x14) = 31;
            }
            const auto borrowed = animation;
            const bool active = phase != 1 && phase != 2;
#ifdef ISAAC_LAN_TEST_J835
            expectState(active, 0, 0, false, phase == 0);
#else
            expectState(active, 0, 0, true, phase == 0);
#endif
            input::edges[14] = true;
            call(controls, object);
            require(nativeHides == (phase == 0 ? 1u : 0u) && animation == borrowed,
                    "Prompt accepted a non-Idle phase or modified a borrowed animation string");
        }
        for (int slot : {0, 1, 3}) {
            reset(slot, true);
            field<Address>(object, 0x34) = reinterpret_cast<Address>(disappearing.data());
            const auto before = game;
            call(controls, object);
            call(render, object);
            require(game == before && !nativeHides && !nativeRenders && !input::queries,
                    "Challenge changed an unfinished prompt animation");
            field<Address>(object, 0x34) = reinterpret_cast<Address>(animation.data());
            call(controls, object);
            call(controls, object);
            require(nativeHides == 1 && field<int>(object, resultOffset) == 2 && !input::queries,
                    "Challenge failed to decline once at Idle on each peer");
        }
        // Leaving a game and entering another must not retain the previous prompt pointer.
        field<Address>(image, backend::globals::game) = 0;
        expectState(false, -1, 0, false, false);
        call(controls, unrelated.data());
        require(nativeControls == 1, "A missing Game intercepted an unrelated prompt");
        std::vector<unsigned char> nextGame = game;
        field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(nextGame.data());
        field<int>(nextGame.data() + promptOffset, selectionOffset) = 1;
        require(prompt::read().selection == 1, "Prompt retained a destroyed Game object");
        require(MH_Uninitialize() == MH_OK, "Remove prompt fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS victory prompt layouts, authority, phases, native ABI and hook cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

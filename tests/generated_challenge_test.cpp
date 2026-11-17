#include "engine/versions/j460/generated_challenge.cpp"
#include "test_support.h"
#include <vector>

extern "C" {
unsigned observedGeneratedFlags = 0, observedGeneratedEAX = 0, observedGeneratedECX = 0;
unsigned observedGeneratedEDX = 0, observedGeneratedEDI = 0, observedGeneratedEBX = 0;
float observedGeneratedScale = 0;
__attribute__((naked)) void generatedStyleReturn() {
    __asm__ __volatile__(
        "pushfl\n\tpopl _observedGeneratedFlags\n\t"
        "movl %eax, _observedGeneratedEAX\n\tmovl %ecx, _observedGeneratedECX\n\t"
        "movl %edx, _observedGeneratedEDX\n\tmovl %edi, _observedGeneratedEDI\n\t"
        "movl %ebx, _observedGeneratedEBX\n\tmovss %xmm2, _observedGeneratedScale\n\tret");
}
__attribute__((naked, fastcall)) void invokeGeneratedStyle(void*, void (*)()) {
    __asm__ __volatile__("pushl %ebx\n\tpushl %edi\n\tpushl %esi\n\t"
                         "movl %edx, %esi\n\tmovl %ecx, %edi\n\tmovl %ecx, %edx\n\t"
                         "movl $0x3f400000, %eax\n\tmovd %eax, %xmm2\n\t"
                         "movl $0xaabbccdd, %eax\n\tmovl $0x11223344, %ebx\n\t"
                         "call *%esi\n\tpopl %esi\n\tpopl %edi\n\tpopl %ebx\n\tret");
}
}
namespace {
unsigned* challengeField;
unsigned expectedChallenge;
bool expectedAlternate;
int __stdcall chestFixture(bool alternate) {
    require(*challengeField == expectedChallenge && alternate == expectedAlternate,
            "Native challenge route query lost its context or ABI argument");
    return 27;
}
} // namespace
int main() {
    using namespace isaac::engine;
    std::vector<unsigned> game((j460::layout::game::challenge + 4) / 4, 0);
    auto gameAddress = reinterpret_cast<std::uintptr_t>(game.data());
    generatedChallengeImage = reinterpret_cast<std::uintptr_t>(&gameAddress) - j460::globals::game;
    static bool enabled = false;
    useGeneratedChallenge = [] { return enabled; };
    challengeField = &game[j460::layout::game::challenge / 4];
    originalChestEnding = chestFixture;
    for (auto target :
         {&isaac_lan_glitched_grid_return, &isaac_lan_glitched_rock_return,
          &isaac_lan_glitched_backdrop_type_return, &isaac_lan_glitched_backdrop_return,
          &isaac_lan_glitched_room_config_return})
        *target = reinterpret_cast<void*>(generatedStyleReturn);
    constexpr unsigned zeroFlag = 0x40;
    for (bool requested : {false, true, false}) {
        enabled = requested;
        for (unsigned challenge : {0u, 21u, 45u}) {
            *challengeField = challenge;
            const auto before = game;
            for (auto thunk : {isaac_lan_glitched_grid, isaac_lan_glitched_rock,
                               isaac_lan_glitched_backdrop_type, isaac_lan_glitched_backdrop,
                               isaac_lan_glitched_room_config}) {
                invokeGeneratedStyle(game.data(), thunk);
                require(((observedGeneratedFlags & zeroFlag) != 0) == (enabled || challenge == 45),
                        "Generated challenge selected the wrong native style branch");
                require(game == before && observedGeneratedEAX == 0xaabbccdd &&
                            observedGeneratedEBX == 0x11223344 &&
                            observedGeneratedECX == gameAddress &&
                            observedGeneratedEDX == gameAddress &&
                            observedGeneratedEDI == gameAddress && observedGeneratedScale == 0.75f,
                        "Style branch mutated game state, GPRs or SSE state");
            }
            expectedChallenge = enabled ? 45 : challenge;
            for (bool alternate : {false, true}) {
                expectedAlternate = alternate;
                require(generatedChestEnding(alternate) == 27 && game == before,
                        "Route query changed return value or retained its native challenge");
            }
            try {
                GeneratedChallengeRewardScope outer;
                require(*challengeField == expectedChallenge, "Reward context missing");
                { GeneratedChallengeRewardScope inner; }
                require(*challengeField == expectedChallenge, "Nested context restored too early");
                throw std::runtime_error("fixture failure");
            } catch (const std::runtime_error& error) {
                require(std::string_view(error.what()) == "fixture failure", error.what());
            }
            require(game == before, "Reward failure leaked a native challenge");
        }
    }
    enabled = true;
    {
        GeneratedChallengeRewardScope scope;
        gameAddress = 0;
    }
    require(*challengeField == 45, "Destroyed game context was accessed during cleanup");
    std::puts("PASS generated challenge native branches, ABI, route queries and scoped cleanup");
}

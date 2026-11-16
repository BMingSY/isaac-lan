#include "engine/versions/j460/boss_intro.h"
#include "test_support.h"
#include <array>

namespace {
namespace field = isaac::engine::j460::layout::roomTransition;
struct Transition {
    std::array<int, 160> storage{};
    int& at(unsigned offset) {
        return storage[offset / sizeof(int)];
    }
    std::uintptr_t address() {
        return reinterpret_cast<std::uintptr_t>(storage.data());
    }
};
void completion() {
    for (int phase : {field::intro, field::returning}) {
        Transition value;
        value.at(field::mode) = phase;
        value.at(field::bossIntro) = 1;
        value.at(field::elapsed) = 3;
        value.at(field::duration) = 15;
        constexpr auto playing = field::introSprite +
                                 isaac::engine::j460::layout::sprite::animation +
                                 isaac::engine::j460::layout::animationState::playing;
        auto& spritePlaying = *reinterpret_cast<bool*>(value.address() + playing);
        spritePlaying = true;
        unsigned calls = 0;
        bool controls = false;
        const auto update = [&] {
            ++calls;
            if (value.at(field::mode) == field::intro) {
                require(!spritePlaying && value.at(field::elapsed) == 3,
                        "Intro completion bypassed native screen cleanup");
                value.at(field::mode) = field::returning;
            } else {
                require(value.at(field::mode) == field::returning &&
                            value.at(field::elapsed) == value.at(field::duration),
                        "Native completion did not receive the finished return phase");
                value.at(field::mode) = 0;
                controls = true;
            }
        };
        isaac::engine::j460::finishBossIntro(value.address(), update);
        require(controls && calls == (phase == field::intro ? 2u : 1u),
                "Boss intro did not complete through the native state machine");
        isaac::engine::j460::finishBossIntro(value.address(), update);
        require(calls == (phase == field::intro ? 2u : 1u), "Completed screen ran cleanup twice");
    }
}
void boundaries() {
    for (int boss : {0, 1})
        for (int phase : {0, 1, 2, 3, 4}) {
            if (boss && (phase == field::intro || phase == field::returning))
                continue;
            Transition value;
            value.at(field::mode) = phase;
            value.at(field::bossIntro) = boss;
            const auto before = value.storage;
            isaac::engine::j460::finishBossIntro(value.address(), [] {
                require(false, "Boss completion entered an unrelated native transition");
            });
            require(value.storage == before, "Boss completion modified an unrelated transition");
        }
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"completion", completion}, {"boundaries", boundaries}});
}

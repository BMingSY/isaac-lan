#pragma once
#include "engine/versions/j460/layout.h"
#include <cstdint>

namespace isaac::engine::j460 {
// Only a live boss versus screen may complete early. Native Update retains
// music, player controls and animation cleanup; no game object is owned here.
template <class Update> void finishBossIntro(std::uintptr_t transition, Update update) {
    namespace field = layout::roomTransition;
    const auto integer = [=](unsigned offset) -> int& {
        return *reinterpret_cast<int*>(transition + offset);
    };
    if (!integer(field::bossIntro))
        return;
    if (integer(field::mode) == field::intro) {
        constexpr auto playing =
            field::introSprite + layout::sprite::animation + layout::animationState::playing;
        *reinterpret_cast<bool*>(transition + playing) = false;
        update();
    }
    if (integer(field::mode) == field::returning) {
        integer(field::elapsed) = integer(field::duration);
        update();
    }
}
} // namespace isaac::engine::j460

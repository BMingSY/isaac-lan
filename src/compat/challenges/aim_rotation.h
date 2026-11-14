#pragma once
#include "core/input_actions.h"

namespace isaac::compat::challenges {
inline constexpr unsigned maximumAimSeats = 4;
inline constexpr unsigned shootingMask =
    (1u << input::action::shootLeft) | (1u << input::action::shootRight) |
    (1u << input::action::shootUp) | (1u << input::action::shootDown);

// Only aiming belongs to the preceding opening seat. Movement, consumables,
// UI and room identity continue to belong to the actor's original owner.
template <class Input> void copyShooting(Input& target, const Input& source) {
    for (int action = input::action::shootLeft; action <= input::action::shootDown; ++action)
        target.values[action] = source.values[action];
    target.triggered = (target.triggered & ~shootingMask) | (source.triggered & shootingMask);
    target.pointer = source.pointer;
}

template <class Inputs> void rotateShooting(Inputs& inputs, unsigned players, unsigned connected) {
    if (players < 2 || players > maximumAimSeats || players > inputs.size())
        return;
    const auto physical = inputs;
    const typename Inputs::value_type neutral{};
    for (unsigned target = 0; target < players; ++target) {
        const auto source = (target + players - 1) % players;
        copyShooting(inputs[target], connected & (1u << source) ? physical[source] : neutral);
    }
}
} // namespace isaac::compat::challenges

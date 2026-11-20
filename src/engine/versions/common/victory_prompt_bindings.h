#pragma once
#include <cstdint>
#include <optional>

namespace isaac::engine::native_victory_prompt {
struct Bindings {
    std::uint32_t controls, render, hide, game;
    unsigned prompt, animation, playing, stringSize, stringCapacity, selection, result;
    std::optional<unsigned> nativeVote;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_victory_prompt

#pragma once
#include <array>
#include <cstdint>

namespace isaac::engine::native_generated_challenge {
struct Bindings {
    std::uint32_t game, challenge, chestEnding;
    std::array<std::uint32_t, 5> styles;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_generated_challenge

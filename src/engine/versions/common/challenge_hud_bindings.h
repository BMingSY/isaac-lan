#pragma once
#include <array>
#include <cstddef>
#include <cstdint>

namespace isaac::engine::native_challenge_hud {
// A borrowed scalar view for HUD::Render only, never a native owned object.
using Parameters = std::array<std::uint32_t, 0xa4 / sizeof(std::uint32_t)>;
enum Register : unsigned { edi, esi, ebp, esp, ebx, edx, ecx, eax };
struct Bindings {
    std::uint32_t destination, parameters;
    Register presenceRegister, parametersRegister;
    std::ptrdiff_t noUnlocks;
    void (*writeParameters)(Parameters&, std::array<int, 2>);
};
extern const Bindings bindings;
} // namespace isaac::engine::native_challenge_hud

#pragma once

namespace isaac::engine::native_mouse {
struct Vector {
    float x = 0, y = 0;
};
using Aim = bool(__attribute__((thiscall)) *)(void*, Vector*, bool);
using ShootingEntity = void*(__attribute__((thiscall)) *)(void*);
inline constexpr float canonicalScale = 0.2f;
enum class Result { passthrough, inactive, active };
// Backend-private synchronous query; the actor and output are borrowed.
using Router = Result (*)(void*, Vector*);
} // namespace isaac::engine::native_mouse

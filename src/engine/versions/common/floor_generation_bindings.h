#pragma once

namespace isaac::engine::native_floor_generation {
// Both signatures begin with CMP dword [EAX + challenge], 21 (seven bytes).
// The hook observes its following conditional branch; native does the compare.
inline constexpr unsigned comparisonBytes = 7;
struct Bindings {
    unsigned count, shape;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_floor_generation

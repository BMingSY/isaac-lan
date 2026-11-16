#pragma once
#include <cstdint>

namespace isaac::engine {
// The callback selects the existing full-size native generation branches.
// It is queried synchronously during generation, including the first floor.
bool installFloorGeneration(std::uintptr_t image, bool (*largeFloor)());
} // namespace isaac::engine

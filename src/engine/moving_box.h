#pragma once
#include <cstdint>

namespace isaac::presentation::moving_box {
bool install(std::uintptr_t image);
bool capture(std::uintptr_t player);
void apply(std::uintptr_t player, bool full);
void reset();
} // namespace isaac::presentation::moving_box

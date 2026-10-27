#pragma once
#include "engine/versions/common/input_query.h"

namespace isaac::engine::j835::input_queries {
// Adapt the original game's three native methods to the shared LAN query ABI.
// original receives a physical-input bypass; it does not reenter the detour.
bool install(std::uintptr_t image, native_input::Detour detour, native_input::Query& original);
} // namespace isaac::engine::j835::input_queries

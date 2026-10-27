#pragma once
#include "engine/versions/common/mouse_query.h"
#include <cstdint>

namespace isaac::engine::j835::mouse_input {
// Original Repentance inlines mouse aiming inside Player::Controls. These two
// boundaries adapt only that block and provide a synchronous physical bypass.
bool install(std::uintptr_t image, native_mouse::Router router, native_mouse::Aim& physical);
} // namespace isaac::engine::j835::mouse_input

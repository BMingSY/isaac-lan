#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;

namespace isaac::presentation::animation {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void reset();
bool active();
} // namespace isaac::presentation::animation

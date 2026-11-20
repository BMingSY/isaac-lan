#pragma once
#include <windows.h>
#include <cstdint>
#include <string_view>

struct lua_State;
namespace isaac::engine::native_sprite {
bool bind(lua_State*, HMODULE, std::uintptr_t image);
// Backend-only borrowed access. Neither lookup transfers native ownership.
std::uintptr_t findLayer(std::uintptr_t sprite, unsigned id);
std::string_view path(std::uintptr_t nativeString);
} // namespace isaac::engine::native_sprite

#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::engine::native_references {
bool bind(lua_State*, HMODULE, std::uintptr_t image);
} // namespace isaac::engine::native_references

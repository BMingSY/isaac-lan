#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::generated_items {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
} // namespace isaac::generated_items

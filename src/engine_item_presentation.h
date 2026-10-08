#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::presentation::items {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void advance();
void reset();
} // namespace isaac::presentation::items

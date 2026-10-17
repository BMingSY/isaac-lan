#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::emotes {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void reset();
} // namespace isaac::emotes

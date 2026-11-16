#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
struct lua_State;
namespace isaac::visuals {
bool bind(lua_State*, HMODULE);
// Copies an active player action; the caller owns the live player reference.
std::string actorDepartureAnimation(std::uintptr_t player);
} // namespace isaac::visuals

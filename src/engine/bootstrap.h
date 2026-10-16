#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
struct lua_State;
namespace isaac::engine::bootstrap {
int installUpdates(std::uintptr_t image, void (*logger)(const std::string&));
int installRendering();
void halfUpdate();
void restorePositions();
bool scopeActive();
bool bind(lua_State* state, HMODULE module);
} // namespace isaac::engine::bootstrap

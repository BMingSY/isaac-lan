#pragma once
#include <windows.h>
#include <cstdint>
#include <functional>
struct lua_State;
namespace isaac::presentation::items {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void advance();
void withActor(void* player, const std::function<void()>& action);
void withScreen(const std::function<void()>& draw);
void reset(bool preservePixels = false);
} // namespace isaac::presentation::items

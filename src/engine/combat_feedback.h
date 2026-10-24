#pragma once
#include <windows.h>
#include <cstdint>
#include <functional>
struct lua_State;
namespace isaac::combat_feedback {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
// Borrow live room sprites only for this draw; restore their complete colors.
void withPresentation(std::uintptr_t room, const std::function<void()>& draw);
} // namespace isaac::combat_feedback

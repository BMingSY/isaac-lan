#pragma once
#include <windows.h>
#include <optional>
struct lua_State;
namespace isaac::chat_input {
bool bind(lua_State*, HMODULE);
std::optional<LRESULT> event(HWND, UINT, WPARAM, LPARAM);
bool capturesInput();
void reset();
} // namespace isaac::chat_input

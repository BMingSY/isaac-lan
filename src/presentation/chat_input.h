#pragma once
#include <windows.h>
#include <optional>
#include <string_view>
struct lua_State;
namespace isaac::chat_input {
enum class TextField { address, port, seed };
void beginField(TextField, std::string_view);
void endField();
bool fieldActive();
std::string_view fieldText();
int fieldKey();
bool bind(lua_State*, HMODULE);
std::optional<LRESULT> event(HWND, UINT, WPARAM, LPARAM);
bool capturesInput();
void reset();
} // namespace isaac::chat_input

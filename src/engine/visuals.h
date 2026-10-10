#pragma once
#include <windows.h>
struct lua_State;
namespace isaac::visuals {
bool bind(lua_State*, HMODULE);
}

#pragma once
#include <windows.h>
struct lua_State;
namespace isaac::engine::native_entity_pose {
bool bind(lua_State*, HMODULE);
} // namespace isaac::engine::native_entity_pose

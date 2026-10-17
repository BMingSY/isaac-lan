#pragma once
#include "engine/lua_api.h"

namespace isaac::lua_state_codec {
// Adds state_encode/state_decode to the table on top of the stack. No game objects,
// layouts or pointers enter this codec; the same binding runs in offline Lua 5.3.
bool bind(lua_State*, lua::Module, lua::Resolver = lua::defaultResolver);
} // namespace isaac::lua_state_codec

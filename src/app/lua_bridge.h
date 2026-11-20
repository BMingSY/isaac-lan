#pragma once
#include <functional>
struct lua_State;
namespace isaac::lua {
struct API;
}
namespace isaac::app {
// The caller owns the Lua state, API lifetime and outer stack restoration.
void loadBridge(lua_State* state, const lua::API& api, const std::function<bool(int, int)>& invoke);
} // namespace isaac::app

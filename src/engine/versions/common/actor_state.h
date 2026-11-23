#pragma once
#include <windows.h>
#include <cstdint>
#include <functional>
#include <vector>
struct lua_State;
namespace isaac::lua {
struct API;
}
namespace isaac::engine::native_actor_state {
struct Callbacks {
    // Return a snapshot of the borrowed native roster. Team queries may outlive
    // a local rendering roster; the addresses are used only in this call.
    std::function<std::vector<std::uintptr_t>(bool team)> roster;
};
bool bind(lua_State*, HMODULE, std::uintptr_t image, const Callbacks&);
void bindCrimeView(lua_State*, const lua::API&, std::uintptr_t image, const Callbacks&);
} // namespace isaac::engine::native_actor_state

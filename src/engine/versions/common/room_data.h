#pragma once
#include <windows.h>
#include <cstdint>
#include <functional>
struct lua_State;
namespace isaac::engine::native_room_data {
struct Callbacks {
    std::function<bool()> enabled, idle;
    // Current scoped room with initialized geometry, on either peer. Excludes storage shells.
    std::function<std::uintptr_t()> loadedRoom;
};
bool bind(lua_State*, HMODULE, std::uintptr_t image, const Callbacks&);
void resetMap();
void withMapPickups(const std::function<void()>& cache);
} // namespace isaac::engine::native_room_data

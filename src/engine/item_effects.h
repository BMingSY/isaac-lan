#pragma once
#include <cstdint>
#include <windows.h>
struct lua_State;
#include <functional>

namespace isaac::engine::items {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void startingRewards(const std::function<void()>& start, bool shared);
void grantStartingRewards(void* player, unsigned slot);
void leaveRoom(void* player);
bool initializeBlueRoom(void* game, int source, int destination, int direction);
} // namespace isaac::engine::items

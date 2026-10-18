#pragma once
#include <cstdint>
#include <functional>

namespace isaac::engine::items {
bool install(std::uintptr_t image);
void startingRewards(const std::function<void()>& start, bool shared);
void grantStartingRewards(void* player, unsigned slot);
void leaveRoom(void* player);
} // namespace isaac::engine::items

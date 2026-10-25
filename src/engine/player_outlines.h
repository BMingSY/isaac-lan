#pragma once
#include <cstdint>
#include <functional>

namespace isaac::presentation::outlines {
bool install(std::uintptr_t image);
// Borrow the connected LAN slots only during the local room's native rendering.
// No player, sprite, online-session or persistent palette state is changed.
void withPlayers(unsigned connected, const std::function<void()>& render);
} // namespace isaac::presentation::outlines

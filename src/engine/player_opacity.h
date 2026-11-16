#pragma once
#include "engine/lua_api.h"
#include <cstdint>
#include <functional>
#include <span>

namespace isaac::presentation::player_opacity {
void configure(unsigned others);
bool bind(lua_State*, lua::Module);
bool install(std::uintptr_t image);
// Borrow player-owned sprites and owners only for this render. Modulate final
// character colors and native tear/laser render opacity without changing simulation.
void withPlayers(std::span<const std::uintptr_t> players, unsigned connected,
                 const std::function<void()>& render);
} // namespace isaac::presentation::player_opacity

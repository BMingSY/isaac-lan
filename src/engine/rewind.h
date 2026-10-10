#pragma once
#include "engine/rooms.h"
#include <span>

struct lua_State;
namespace isaac::rewind {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void remember(unsigned slot, int door, const std::vector<rooms::SavedLocation>& locations);
bool request(unsigned slot);
bool executePending();
void reset();
} // namespace isaac::rewind

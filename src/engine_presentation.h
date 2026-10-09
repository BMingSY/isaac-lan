#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::presentation {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void roomEntered(std::uintptr_t room);
void reset();
unsigned playedIntro();
bool introActive();
void observeIntro(unsigned slot, unsigned serial, bool active);
bool roomPaused();
} // namespace isaac::presentation

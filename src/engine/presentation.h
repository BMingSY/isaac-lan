#pragma once
#include <windows.h>
#include <cstdint>
struct lua_State;
namespace isaac::presentation {
// Preserve the native versus screen while simulating independent rooms.
class IntroSimulationScope {
    std::uintptr_t transition = 0;
    int saved = 0;

  public:
    explicit IntroSimulationScope(bool advance = false);
    ~IntroSimulationScope();
    IntroSimulationScope(const IntroSimulationScope&) = delete;
};
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void roomEntered(std::uintptr_t room);
void reset();
unsigned playedIntro();
bool introActive();
void observeIntro(unsigned slot, unsigned serial, bool active);
bool roomPaused();
} // namespace isaac::presentation

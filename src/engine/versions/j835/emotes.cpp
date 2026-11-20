#include "engine/emotes.h"

// The original game has no native online emote wheel or bubbles. Its profile
// disables install/bind; reset is shared by the frontend and chat lifecycle.
namespace isaac::emotes {
bool install(std::uintptr_t) {
    return false;
}
bool bind(lua_State*, HMODULE) {
    return false;
}
void reset() {}
} // namespace isaac::emotes

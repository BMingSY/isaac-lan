#pragma once
#include <windows.h>
#include <cstdint>
#include <array>
struct lua_State;
namespace isaac::audio {
bool install(std::uintptr_t image);
bool bind(lua_State*, HMODULE);
void reset();
void present();
class RoomScope {
    std::uintptr_t manager = 0;
    std::array<unsigned, 2> previous{};

  public:
    RoomScope();
    ~RoomScope();
};
} // namespace isaac::audio

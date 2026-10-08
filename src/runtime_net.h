#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include <span>

struct lua_State;
namespace isaac::lan {
struct RoomRequest;
}
namespace isaac::runtime {
void requestWindowClose();
bool install(std::uintptr_t image, void (*logger)(const std::string&), void (*halfUpdate)(),
             void (*restorePositions)());
bool bind(lua_State* state, HMODULE luaModule);
bool halfAllowed();
void halfStarted();
void halfCompleted();
int localViewSlot();
bool replica();
void present();
void beginStage(bool same, int animation, bool rKey = false);
void beginRewind(std::span<const std::uint8_t> bytes);
bool requestRoom(const lan::RoomRequest&);
std::uint32_t tick();
void abort(const std::string& error);
void beforeExit(bool save);
void afterExit(bool save);
} // namespace isaac::runtime

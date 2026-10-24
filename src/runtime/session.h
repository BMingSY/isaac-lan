#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include <span>
#include <array>

struct lua_State;
namespace isaac::lan {
struct RoomRequest;
}
namespace isaac::runtime {
void configureNetwork(unsigned hz);
void roomEntered();
void requestWindowClose();
bool install(std::uintptr_t image, void (*logger)(const std::string&), void (*halfUpdate)(),
             void (*restorePositions)());
bool bind(lua_State* state, HMODULE luaModule);
bool halfAllowed();
void halfStarted();
void halfCompleted();
int localViewSlot();
bool replica();
bool challengeActive();
bool takeCollectiblePickup(int owner, unsigned actorSeed, int item, int charge, bool touched,
                           int varData, int pool);
std::array<int, 2> challengeDestination();
bool allowRoomEntry(unsigned slot, int fromDimension, int fromRoom, int dimension, int room,
                    bool teleport);
int craftingBagViewTarget();
unsigned difficulty();
bool startingPartyHasCharacter(int kind);
bool ending();
void present();
void refreshAutomation(std::uint32_t renderFrame);
void pollLocalConsole();
void beginStage(bool same, int animation, unsigned restart = 0, unsigned cinematic = 0);
void prepareEnding();
bool beginEnding(unsigned ending, bool completed = false);
void beginRewind(std::span<const std::uint8_t> bytes);
bool requestRoom(const lan::RoomRequest&);
std::uint32_t tick();
std::uint32_t worldEpoch();
void abort(const std::string& error);
void beforeExit(bool save);
void afterExit(bool save);
} // namespace isaac::runtime

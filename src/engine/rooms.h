#pragma once
#include "runtime/saved_location.h"
#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>
#include <functional>

struct lua_State;
namespace isaac::lan {
struct RoomRequest;
}
namespace isaac::rooms {
bool finalCombat();
using RoomCall = void(__attribute__((thiscall)) *)(void*);
bool install(std::uintptr_t image, void (*logger)(const std::string&));
bool bind(lua_State*, HMODULE);
bool update(void* room, RoomCall original);
bool half(void (*original)());
bool render(void* game, RoomCall original, int slot);
bool backgroundLoading();
void withView(const std::function<void()>& draw, bool localPlayersOnly = false);
void withMapPickups(const std::function<void()>& cache);
void finishFrame();
void presentCamera();
void requestExit(bool save);
void playEnding(unsigned ending);
void beforeStart();
void resumeAfterTransition(std::vector<SavedLocation> locations);
std::vector<SavedLocation> captureLocations();
bool restoreLocations(const std::vector<SavedLocation>&);
void setConnected(unsigned mask);
unsigned connected();
unsigned soundAudience();
std::uintptr_t presentationPlayer(void* explicitPlayer = nullptr);
bool withPlayer(unsigned slot, const std::function<void()>& call);
bool withRoomPlayers(unsigned slot, const std::function<void()>& call);
bool gatherForTransition(const std::function<void()>& begin);
void protectArrivals(unsigned mask);
bool receiveRoomRequest(unsigned slot, const lan::RoomRequest&);
bool checkpointReady();
bool stateReady();
bool viewReady();
bool virtualized();
bool withCheckpointRoster(const std::function<void()>& capture);
bool takeFloorChange();
} // namespace isaac::rooms

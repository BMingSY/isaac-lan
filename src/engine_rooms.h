#pragma once
#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>
#include <functional>

struct lua_State;
namespace isaac::lan { struct RoomRequest; }
namespace isaac::rooms {
using RoomCall = void(__attribute__((thiscall))*)(void*);
bool install(std::uintptr_t image, void (*logger)(const std::string&));
bool bind(lua_State*, HMODULE);
bool update(void* room, RoomCall original);
bool half(void (*original)());
bool render(void* game, RoomCall original, int slot);
bool backgroundLoading();
void withView(const std::function<void()>& draw, bool localPlayersOnly=false);
void finishFrame();
void presentCamera();
void requestExit(bool save);
void beforeStart();
struct SavedLocation { int dimension, index; float x,y; };
void resumeAfterTransition(std::vector<SavedLocation> locations);
std::vector<SavedLocation> captureLocations();
bool restoreLocations(const std::vector<SavedLocation>&);
void setConnected(unsigned mask);
unsigned connected();
unsigned soundAudience();
void protectArrivals(unsigned mask);
bool receiveRoomRequest(unsigned slot,const lan::RoomRequest&);
bool checkpointReady();
bool stateReady();
bool virtualized();
bool withCheckpointRoster(const std::function<void()>& capture);
bool takeFloorChange();
}

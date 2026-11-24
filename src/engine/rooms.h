#pragma once
#include "runtime/saved_location.h"
#include <windows.h>
#include <cstdint>
#include <string>
#include <vector>
#include <functional>
#include <optional>

struct lua_State;
namespace isaac::lan {
struct RoomRequest;
}
namespace isaac::rooms {
bool finalCombat();
bool install(std::uintptr_t image, void (*logger)(const std::string&));
bool bind(lua_State*, HMODULE);
bool backgroundLoading();
void withView(const std::function<void()>& draw, bool localPlayersOnly = false);
void withMapPickups(const std::function<void()>& cache);
void finishFrame();
void presentCamera();
void requestExit(bool save);
void playEnding(unsigned ending);
void finishChallenge();
void beforeStart(bool preserveItemPixels = false);
bool prepareRewind(unsigned slot);
void resumeAfterTransition(std::vector<SavedLocation> locations);
std::vector<SavedLocation> captureLocations();
bool restoreLocations(const std::vector<SavedLocation>&);
void setConnected(unsigned mask);
unsigned connected();
struct SoundRoom {
    int dimension = 0, index = 0;
    unsigned audience = 0;
};
std::optional<SoundRoom> soundRoom(const void* room);
unsigned soundAudience();
bool withPlayer(unsigned slot, const std::function<void()>& call);
bool withRoomPlayers(unsigned slot, const std::function<void()>& call);
bool gatherForTransition(const std::function<void()>& begin);
void protectArrivals(unsigned mask);
bool receiveRoomRequest(unsigned slot, const lan::RoomRequest&);
bool checkpointReady();
bool stateReady();
int currentRoomIndex();
bool viewReady();
bool virtualized();
bool withCheckpointRoster(const std::function<void()>& capture);
bool takeFloorChange();
int floorSourceRoom();
} // namespace isaac::rooms

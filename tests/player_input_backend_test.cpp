#include "test_support.h"
#include "engine/versions/common/player_input.h"
#ifdef ISAAC_LAN_TEST_REPENTANCE
#include "engine/versions/repentance/entrypoints.h"
#else
#include "engine/versions/repentance_plus/entrypoints.h"
#endif
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <array>
#include <cstring>
#include <vector>

namespace {
namespace players = isaac::engine::native_players;
using Address = std::uintptr_t;
#ifdef ISAAC_LAN_TEST_REPENTANCE
namespace backend = isaac::engine::repentance;
constexpr unsigned managerOffset = 0x1ba40, rosterOffset = 0x1ba50, controllerOffset = 0x154c;
constexpr unsigned positionX = 0x294, positionY = 0x298, previousX = 0x29c, previousY = 0x2a0;
constexpr unsigned hudOffset = 0x3da4c;
constexpr auto spawnRva = backend::entry::playerManagerSpawn;
constexpr auto assignRva = backend::entry::playerAssignController;
constexpr auto initializeRva = backend::entry::playerInitialize;
constexpr auto getHUDRva = backend::entry::gameGetHUD;
constexpr auto assignHUDsRva = backend::entry::hudAssignPlayers;
#else
namespace backend = isaac::engine::repentance_plus;
constexpr unsigned managerOffset = 0x1baa8, rosterOffset = 0x1baa8, controllerOffset = 0x161c;
constexpr unsigned positionX = 0x33c, positionY = 0x340, previousX = 0x344, previousY = 0x348;
constexpr unsigned hudOffset = 0x1da04;
constexpr auto spawnRva = backend::entry::engineInputSpawn;
constexpr auto assignRva = backend::entry::engineRoomsAssign;
constexpr auto initializeRva = backend::entry::engineInputInitialize;
constexpr auto getHUDRva = backend::entry::engineRoomsGetHUD;
constexpr auto assignHUDsRva = backend::entry::engineRoomsRoomCall_5a8620;
#endif
constexpr unsigned imageSize = privateGameImageBytes;
unsigned char* image;
std::vector<unsigned char> game(0x41000, 0xa5);
std::array<std::array<unsigned char, 0x2700>, 8> actors;
std::array<Address, 8> roster, relocated, rewarded;
std::vector<char> calls;
unsigned count = 1, createdSlot;
int desiredType = 19, desiredController = 3;
bool failSpawn = false, expandInit = true, expandReward = true, replaceGame = false;
template <class T> T& field(void* memory, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(memory) + offset);
}
Address address(const void* p) {
    return reinterpret_cast<Address>(p);
}
void publish(std::array<Address, 8>& entries) {
    field<Address>(game.data(), rosterOffset) = address(entries.data());
    field<Address>(game.data(), rosterOffset + 4) = address(entries.data() + count);
    field<Address>(game.data(), rosterOffset + 8) = address(entries.data() + entries.size());
}
void __attribute__((thiscall)) assign(void* player, int controller, bool propagate) {
    require(controller == desiredController && propagate,
            "Native assignment must receive controller and companion propagation in ABI order");
    calls.push_back('A');
    field<int>(player, controllerOffset) = controller;
}
void* __attribute__((thiscall)) spawn(void* manager, int type) {
    require(manager == game.data() + managerOffset && type == desiredType,
            "PlayerManager receiver must not be confused with its roster subobject");
    calls.push_back('S');
    if (failSpawn)
        return nullptr;
    createdSlot = count++;
    roster[createdSlot] = address(actors[createdSlot].data());
    publish(roster);
    return actors[createdSlot].data();
}
void __attribute__((thiscall)) initialize(void* player) {
    require(player == actors[createdSlot].data() &&
                field<int>(player, controllerOffset) == desiredController,
            "Native initialization ran before controller assignment");
    calls.push_back('I');
    if (replaceGame) {
        field<Address>(image, backend::globals::game) = 0;
        return;
    }
    if (expandInit) {
        relocated = roster;
        relocated[count] = address(actors[count].data());
        ++count;
        publish(relocated);
        roster.fill(0); // Old allocation is no longer valid after native initialization.
    }
}
void rewards(void* player, unsigned slot) {
    require(player == actors[createdSlot].data() && slot == unsigned(desiredController - 1) &&
                calls.back() == 'I',
            "Starting rewards must follow native initialization with the LAN slot");
    calls.push_back('R');
    if (expandReward) {
        rewarded = relocated;
        rewarded[count] = address(actors[count].data());
        ++count;
        publish(rewarded);
        relocated.fill(0);
    }
}
void* __attribute__((thiscall)) getHUD(void* receiver) {
    require(receiver == game.data(), "GetHUD receiver");
    calls.push_back('G');
    return game.data() + hudOffset;
}
void __attribute__((thiscall)) assignHUDs(void* receiver) {
    require(receiver == game.data() + hudOffset, "AssignPlayerHUDs receiver");
    for (auto i = createdSlot; i < count; ++i)
        require(field<int>(actors[i].data(), controllerOffset) == desiredController &&
                    field<float>(actors[i].data(), positionX) == 70 + 12 * desiredController &&
                    field<float>(actors[i].data(), positionY) == 90 &&
                    field<float>(actors[i].data(), previousX) == 70 + 12 * desiredController &&
                    field<float>(actors[i].data(), previousY) == 90,
                "All newly appended bodies must be assigned and placed before HUD assignment");
    calls.push_back('H');
}
void reset() {
    calls.clear();
    count = 1;
    failSpawn = replaceGame = false;
    expandInit = expandReward = true;
    desiredController = 3;
    for (auto& player : actors)
        player.fill(0xa5);
    for (unsigned i = 0; i < roster.size(); ++i)
        roster[i] = address(actors[i].data());
    field<int>(actors[0].data(), controllerOffset) = 1;
    field<float>(actors[0].data(), positionX) = 70;
    field<float>(actors[0].data(), positionY) = 90;
    field<Address>(image, backend::globals::game) = address(game.data());
    publish(roster);
}
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image, "Allocate independent native-player image");
    const auto patch = [&](unsigned rva, auto fn) {
        image[rva] = 0xe9;
        field<std::uint32_t>(image, rva + 1) = static_cast<std::uint32_t>(
            address(reinterpret_cast<void*>(fn)) - address(image) - rva - 5);
    };
    patch(spawnRva, spawn);
    patch(assignRva, assign);
    patch(initializeRva, initialize);
    patch(getHUDRva, getHUD);
    patch(assignHUDsRva, assignHUDs);
    require(FlushInstructionCache(GetCurrentProcess(), image, imageSize), "Publish x86 stubs");
    reset();
}
void assignment() {
    const auto before = actors[0];
    require(players::assign(address(image), 0, desiredController), "Valid native assignment");
    auto expected = before;
    field<int>(expected.data(), controllerOffset) = desiredController;
    require(actors[0] == expected, "Assignment wrote outside the audited controller field");
    calls.clear();
    require(!players::assign(0, 0, 1) && !players::assign(address(image), 1, 1) &&
                !players::assign(address(image), 0, 0) && !players::assign(address(image), 0, 5),
            "Invalid assignment was accepted");
    roster[0] = 0;
    require(!players::assign(address(image), 0, 1) && calls.empty(),
            "Missing actor reached native assignment");
}
void spawning() {
    reset();
    const auto first = actors[0];
    const auto originalGame = game;
    require(players::spawn(address(image), desiredType, desiredController, rewards) == 1,
            "Spawn must return the pre-initialization roster slot");
    require(calls == std::vector<char>({'S', 'A', 'I', 'R', 'A', 'A', 'A', 'G', 'H'}),
            "Spawn, initialization, rewards, companions and HUD order changed");
    require(actors[0] == first, "Joining a player changed the existing actor");
    auto expectedGame = originalGame;
    std::memcpy(expectedGame.data() + rosterOffset, game.data() + rosterOffset, 12);
    require(game == expectedGame, "Spawn mutated unrelated Game or PlayerManager fields");
    for (unsigned i = 1; i < count; ++i) {
        auto expected = actors[i];
        field<int>(expected.data(), controllerOffset) = static_cast<int>(0xa5a5a5a5);
        for (auto offset : {positionX, positionY, previousX, previousY})
            field<std::uint32_t>(expected.data(), offset) = 0xa5a5a5a5;
        std::array<unsigned char, 0x2700> pristine;
        pristine.fill(0xa5);
        require(expected == pristine, "Spawn placement touched adjacent native fields");
    }
    // Reuse the new roster for another join; no component state may retain its
    // old begin/end, and existing companions must keep their original identity.
    roster = rewarded;
    publish(roster);
    expandInit = expandReward = false;
    desiredController = 4;
    calls.clear();
    require(players::spawn(address(image), desiredType, desiredController, rewards) == 4 &&
                calls == std::vector<char>({'S', 'A', 'I', 'R', 'A', 'G', 'H'}),
            "Repeated joining reused stale native roster state");
    require(field<int>(actors[1].data(), controllerOffset) == 3,
            "Repeated joining reassigned an existing companion");
}
void failures() {
    reset();
    require(!players::spawn(0, 0, 1, rewards) && !players::spawn(address(image), -1, 1, rewards) &&
                !players::spawn(address(image), 65536, 1, rewards) &&
                !players::spawn(address(image), 0, 0, rewards) &&
                !players::spawn(address(image), 0, 5, rewards) && calls.empty(),
            "Invalid spawn parameters reached native code");
    for (auto end :
         {address(roster.data()) - 4, address(roster.data()) + 1, address(roster.data()) + 36}) {
        field<Address>(game.data(), rosterOffset + 4) = end;
        require(!players::spawn(address(image), desiredType, desiredController, rewards) &&
                    calls.empty(),
                "Malformed roster reached native spawn");
    }
    reset();
    failSpawn = true;
    const auto before = game;
    require(!players::spawn(address(image), desiredType, desiredController, rewards) &&
                calls == std::vector<char>{'S'} && game == before,
            "Failed native creation reached initialization, rewards or HUD");
    reset();
    replaceGame = true;
    require(!players::spawn(address(image), desiredType, desiredController, rewards) &&
                calls == std::vector<char>({'S', 'A', 'I'}),
            "Destroyed game was reused after native initialization");
    reset();
    require(players::spawn(address(image), desiredType, desiredController, rewards) == 1,
            "A failed session contaminated subsequent player creation");
}
} // namespace
int main() {
    setup();
    assignment();
    spawning();
    failures();
    require(VirtualFree(image, 0, MEM_RELEASE), "Release independent native-player image");
}

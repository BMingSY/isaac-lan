#include "engine_rooms.h"
#include "engine_visuals.h"
#include "engine_audio.h"
#include "engine_input.h"
#include "engine_rewind.h"
#include "engine_presentation.h"
#include "engine_item_presentation.h"
#include "runtime_net.h"
#include "net_protocol.h"
#include "laser_state.h"
#include "room_map.h"
#include "actor_roster.h"
#include "poop_state.h"
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <vector>
#include <bit>
#include <cmath>

namespace isaac::rooms {
namespace {
using Address = std::uintptr_t;
struct Vec2 {
    float x, y;
};
Address image;
void (*logger)(const std::string&);
template <class T> T& at(Address p, std::size_t n) {
    return *reinterpret_cast<T*>(p + n);
}
template <class T> T engine(Address rva) {
    return reinterpret_cast<T>(image + rva);
}
Address game() {
    return at<Address>(image, 0x871678);
}
using Allocate = void*(__cdecl*)(std::size_t);
using Delete = void(__cdecl*)(void*, std::size_t);
void* allocate(std::size_t size) {
    return engine<Allocate>(0x60f4c0)(size);
}
void release(Address p, std::size_t size) {
    if (p)
        engine<Delete>(0x6ef15c)(reinterpret_cast<void*>(p), size);
}
struct Vector {
    Address begin = 0, end = 0, capacity = 0;
};
static_assert(sizeof(Vector) == 12);
Vector& roster() {
    return at<Vector>(game(), 0x1baa8);
}
std::vector<Address> values(const Vector& v) {
    if (!v.begin)
        return {};
    return {reinterpret_cast<Address*>(v.begin), reinterpret_cast<Address*>(v.end)};
}
void assign(Vector& v, const std::vector<Address>& players) {
    const auto needed = players.size() * sizeof(Address);
    if (needed > v.capacity - v.begin) {
        const auto size = std::max<std::size_t>(needed * 2, 128);
        const auto next = reinterpret_cast<Address>(allocate(size));
        if (!next) {
            logger("rooms_fatal=allocation");
            TerminateProcess(GetCurrentProcess(), 92);
        }
        release(v.begin, v.capacity - v.begin);
        v = {next, next, next + size};
    }
    if (needed)
        std::memcpy(reinterpret_cast<void*>(v.begin), players.data(), needed);
    v.end = v.begin + needed;
}
struct Key {
    int dimension, index;
    auto operator<=>(const Key&) const = default;
};
// Only scalar fields are virtualized. Engine containers, sprites and cameras
// retain their native owners; no MSVC STL object is copied through MinGW.
constexpr std::array<std::size_t, 32> contextOffsets = {
    0x18304, 0x18308, 0x1830c, 0x18310, 0x18318, 0x1831c, 0x182c8, 0x1ad90,
    // EntityList::Update writes these HUD boss-health caches for its room.
    0x22e94, 0x22e98, 0x22e9c,
    // Room::Init resets the global color modifier. Every occupied room must
    // retain its own current/target/lerp values, including background entries.
    0x676b4, 0x676b8, 0x676bc, 0x676c0, 0x676c4, 0x676c8, 0x676cc, 0x676d0, 0x676d4, 0x676d8,
    0x676dc, 0x676e0, 0x676e4, 0x676e8, 0x676ec, 0x676f0, 0x676f4, 0x676f8, 0x676fc, 0x26538,
    0x2653c};
struct AmbushState {
    Vector pendingWaves;
    std::array<std::uint32_t, 13> scalars{};
};
static_assert(sizeof(AmbushState) == 0x40);
struct Room;
Room* sharedOwner = nullptr;
void selectSharedState(Room* room);
// J460's room-sized postprocess buffers are process globals. Their native
// shared-pointer pairs must move with the room, including reference owners.
// Keeping only fx_ray isolated lets a 2x2 room overwrite a 1x1 room's surfaces.
constexpr std::array<unsigned, 27> renderImages = {
    0x879758, 0x879774, 0x879794, 0x87979c, 0x8797a4, 0x8797ac, 0x8797b4, 0x8797bc, 0x8797c4,
    0x8797cc, 0x8797d4, 0x8797dc, 0x8797e4, 0x8797ec, 0x8797f4, 0x8797fc, 0x879804, 0x87980c,
    0x879814, 0x87981c, 0x879824, 0x87982c, 0x879834, 0x87983c, 0x879844, 0x87984c, 0x879854};
struct Room {
    Key key;
    Address pointer;
    bool owned;
    std::array<std::uint32_t, contextOffsets.size()> context{};
    Vector scratch;
    AmbushState ambush;
    std::array<std::array<Address, 2>, renderImages.size()> images{};
    // A guest retains remote actors for the vanilla multiplayer HUD, without
    // loading their rooms, running their entry logic, or allocating backdrops.
    bool replicaShell = false;
    bool graphicsRefresh = true;
    unsigned char sceneSnapshot = 0;
    unsigned updates = 0, halves = 0;
    Room() {
        // The leading Ambush vector is immutable XML configuration. Each room
        // owns only its shuffled pending-wave vector, counters and RNGs.
        ambush.scalars = at<AmbushState>(game(), 0x265d4).scalars;
        ambush.scalars[2] = ambush.scalars[3] = ambush.scalars[4] = 0;
    }
    void capture() {
        for (unsigned i = 0; i < context.size(); ++i)
            context[i] = at<std::uint32_t>(game(), contextOffsets[i]);
        graphicsRefresh = at<bool>(game(), 0x26534);
        sceneSnapshot = at<unsigned char>(game(), 0x26540);
    }
    void activate() {
        selectSharedState(this);
        at<Address>(game(), 0x18300) = pointer;
        for (unsigned i = 0; i < context.size(); ++i)
            at<std::uint32_t>(game(), contextOffsets[i]) = context[i];
        at<bool>(game(), 0x26534) = graphicsRefresh;
        at<unsigned char>(game(), 0x26540) = sceneSnapshot;
    }
};
void selectSharedState(Room* room) {
    if (room == sharedOwner)
        return;
    auto& engineState = at<AmbushState>(game(), 0x265d4);
    // Exchange ownership instead of copying an MSVC vector or its elements.
    // Room::Init also replaces the process-wide fx_ray texture. Keep the
    // native reference owner with its room; raw pointer copies would dangle
    // when another room releases or replaces that texture.
    if (sharedOwner) {
        std::swap(sharedOwner->ambush, engineState);
        for (unsigned i = 0; i < renderImages.size(); ++i)
            std::swap(sharedOwner->images[i], at<std::array<Address, 2>>(image, renderImages[i]));
    }
    if (room) {
        std::swap(room->ambush, engineState);
        for (unsigned i = 0; i < renderImages.size(); ++i)
            std::swap(room->images[i], at<std::array<Address, 2>>(image, renderImages[i]));
    }
    sharedOwner = room;
}
std::map<Key, std::unique_ptr<Room>> loaded;
std::map<Address, Room*> location;
std::vector<Address> participants;
bool floorChanged = false;
struct Dormant {
    std::unique_ptr<Room> room;
    std::vector<Address> actors;
    SavedLocation saved;
};
std::map<unsigned, Dormant> dormant;
unsigned connectedMask = 15;
unsigned slotOf(Address player, unsigned fallback = 0) {
    const auto controller = at<int>(player, 0x1618);
    return controller >= 1 && controller <= 4 ? static_cast<unsigned>(controller - 1) : fallback;
}
Address participant(unsigned slot) {
    for (auto p : participants)
        if (slotOf(p) == slot)
            return p;
    return 0;
}
std::vector<Address> logicalPlayers(bool useControllers = true) {
    std::vector<Address> result;
    for (auto player : values(roster())) {
        if (at<unsigned>(player, 0x2c) != 0 || at<Address>(player, 0x3bc))
            continue;
        const auto twin = at<Address>(player, 0x1e68);
        if (twin && at<int>(player, 0x161c) > at<int>(twin, 0x161c))
            continue;
        const int controller = at<int>(player, 0x1618);
        if (useControllers && controller >= 1 && controller <= 4 &&
            std::any_of(result.begin(), result.end(),
                        [controller](Address p) { return at<int>(p, 0x1618) == controller; }))
            continue;
        result.push_back(player);
    }
    if (useControllers && std::all_of(result.begin(), result.end(), [](Address p) {
            return at<int>(p, 0x1618) >= 1 && at<int>(p, 0x1618) <= 4;
        }))
        std::sort(result.begin(), result.end(),
                  [](Address a, Address b) { return at<int>(a, 0x1618) < at<int>(b, 0x1618); });
    return result;
}
std::vector<Address> controlledActors(Address head) {
    std::vector<Address> result;
    const int controller = at<int>(head, 0x1618);
    for (auto player : values(roster()))
        if (player == head ||
            (controller >= 1 && controller <= 4 && at<int>(player, 0x1618) == controller) ||
            at<Address>(head, 0x1e68) == player || at<Address>(player, 0x1e68) == head)
            result.push_back(player);
    return result;
}
Room* active = nullptr;
unsigned depth = 0;
Vector* teamRoster = nullptr;
bool enabled = false, transferring = false;
Address skipSave = 0;
struct Request {
    Address player;
    Key destination;
    int door;
    bool teleport;
    bool animateDeparture;
};
std::vector<Request> pending;
std::set<unsigned> pendingItemRevival;
struct StageRequest {
    bool same;
    int animation;
    Address player;
};
std::optional<StageRequest> pendingStage;
struct TeamTransition {
    Key room;
    std::function<void()> begin;
};
std::optional<TeamTransition> pendingTeamTransition;
bool pendingRKey = false;
std::optional<Address> pendingDogma;
RoomCall originalNativeRoomChange;
void __attribute__((fastcall)) nativeRoomChange(void* transition, void*) {
    // Dogma immediately calls ChangeRoom after StartRoomTransition. Defer both
    // halves until the source room scope has unwound.
    if (!pendingDogma)
        originalNativeRoomChange(transition);
}
using RKey = void(__cdecl*)();
RKey originalRKey;
std::optional<bool> pendingExit;
bool resumeStage = false;
std::vector<SavedLocation> resumeLocations;
bool restoringSavedLocations = false;
using StageTransition = void(__attribute__((thiscall)) *)(void*, bool, int, void*);
StageTransition originalStage;
using LeaveRoom = void(__attribute__((thiscall)) *)(void*, bool);
LeaveRoom originalLeave;
std::set<Address> preparedDepartures;
void __attribute__((fastcall)) leaveRoom(void* player, void*, bool stage) {
    originalLeave(player, stage);
    if (enabled)
        preparedDepartures.insert(reinterpret_cast<Address>(player));
}
std::vector<Address> occupants(const Room& room) {
    std::vector<Address> result;
    for (auto player : values(roster())) {
        auto it = location.find(player);
        if (it != location.end() && it->second == &room)
            result.push_back(player);
    }
    return result;
}
struct Scope {
    Room& room;
    Room* parent;
    Room* previousShared;
    Address previousRoom;
    std::array<std::uint32_t, contextOffsets.size()> previous;
    bool previousRefresh;
    unsigned char previousSnapshot;
    Vector previousRoster;
    Vector nestedScratch;
    Vector* storage;
    std::optional<audio::RoomScope> audioScope;
    bool reconcilePlayers;
    std::vector<Address> originalPlayers;
    std::map<Address, int> originalControllers;
    Scope(Room& target, const std::vector<Address>& players, bool reconcile = true)
        : room(target), parent(active), previousShared(sharedOwner),
          previousRoom(at<Address>(game(), 0x18300)), previousRoster(roster()),
          reconcilePlayers(reconcile), originalPlayers(players) {
        for (auto player : players)
            originalControllers[player] = at<int>(player, 0x1618);
        for (unsigned i = 0; i < previous.size(); ++i)
            previous[i] = at<std::uint32_t>(game(), contextOffsets[i]);
        previousRefresh = at<bool>(game(), 0x26534);
        previousSnapshot = at<unsigned char>(game(), 0x26540);
        if (depth == 0)
            teamRoster = &previousRoster;
        // A display callback can scope the same room again. Its temporary
        // roster must not overwrite an outer scope's live allocation.
        storage = depth ? &nestedScratch : &room.scratch;
        assign(*storage, players);
        roster() = *storage;
        room.activate();
        active = &room;
        ++depth;
        audioScope.emplace();
    }
    explicit Scope(Room& target) : Scope(target, occupants(target)) {}
    ~Scope() {
        audioScope.reset();
        room.capture();
        *storage = roster();
        const auto current = values(*storage);
        roster() = previousRoster;
        // Native player transformations can change the scoped vector. Reconcile
        // those changes into the full roster instead of writing into a slice of
        // the game's original allocation.
        if (reconcilePlayers) {
            auto all = actors::reconcile(
                values(roster()), originalPlayers, current, [&](Address old, Address candidate) {
                    return originalControllers.at(old) == at<int>(candidate, 0x1618);
                });
            for (auto player : originalPlayers)
                if (std::find(current.begin(), current.end(), player) == current.end()) {
                    location.erase(player);
                }
            for (auto player : current)
                if (std::find(originalPlayers.begin(), originalPlayers.end(), player) ==
                    originalPlayers.end())
                    location[player] = &room;
            if (all != values(roster()))
                assign(roster(), all);
            for (unsigned i = 0; i < all.size(); ++i)
                if (std::find(originalPlayers.begin(), originalPlayers.end(), all[i]) ==
                        originalPlayers.end() &&
                    std::find(current.begin(), current.end(), all[i]) != current.end())
                    logger("actor_replaced index=" + std::to_string(i) +
                           " type=" + std::to_string(at<int>(all[i], 0x13c0)) +
                           " controller=" + std::to_string(at<int>(all[i], 0x1618)) +
                           " parent=" + std::to_string(at<Address>(all[i], 0x3bc)) +
                           " twin=" + std::to_string(at<Address>(all[i], 0x1e68)));
            if (depth == 1)
                participants = logicalPlayers();
        }
        at<Address>(game(), 0x18300) = previousRoom;
        for (unsigned i = 0; i < previous.size(); ++i)
            at<std::uint32_t>(game(), contextOffsets[i]) = previous[i];
        at<bool>(game(), 0x26534) = previousRefresh;
        at<unsigned char>(game(), 0x26540) = previousSnapshot;
        active = parent;
        selectSharedState(previousShared);
        if (storage == &nestedScratch)
            release(nestedScratch.begin, nestedScratch.capacity - nestedScratch.begin);
        if (--depth == 0)
            teamRoster = nullptr;
    }
};
struct TeamScope {
    Vector saved;
    bool changed;
    TeamScope() : saved(roster()), changed(enabled && teamRoster) {
        if (changed)
            roster() = *teamRoster;
    }
    ~TeamScope() {
        if (changed) {
            *teamRoster = roster();
            roster() = saved;
        }
    }
};
using ReplacePlayer = bool(__attribute__((thiscall)) *)(void*, void*, void*);
ReplacePlayer originalReplacePlayer;
bool __attribute__((fastcall)) replacePlayer(void* manager, void*, void* oldPlayer,
                                             void* nextPlayer) {
    const auto old = reinterpret_cast<Address>(oldPlayer),
               next = reinterpret_cast<Address>(nextPlayer);
    // Birthright's listed Lazarus bodies are swapped by their GLOBAL indices.
    // A room-local roster can contain both bodies at different indices.
    if (!enabled || !teamRoster || !at<bool>(next, 0x170))
        return originalReplacePlayer(manager, oldPlayer, nextPlayer);
    const auto scoped = values(roster());
    const auto oldIndex = at<unsigned>(old, 0x161c), nextIndex = at<unsigned>(next, 0x161c);
    if (oldIndex < scoped.size() && nextIndex < scoped.size() && scoped[oldIndex] == old &&
        scoped[nextIndex] == next)
        return originalReplacePlayer(manager, oldPlayer, nextPlayer);
    bool replaced;
    std::vector<Address> all;
    {
        TeamScope team;
        replaced = originalReplacePlayer(manager, oldPlayer, nextPlayer);
        all = values(roster());
    }
    if (replaced)
        assign(roster(), actors::replacementView(all, scoped, old, next));
    return replaced;
}
using AddResource = void(__attribute__((thiscall)) *)(void*, int);
using SyncResources = void(__attribute__((thiscall)) *)(void*, unsigned);
using CopyResources = void(__attribute__((thiscall)) *)(void*, void*, unsigned);
AddResource originalCoins;
SyncResources originalResources;
void __attribute__((fastcall)) addCoins(void* player, void*, int delta) {
    // Deep Pockets' cap is a team property across occupied rooms.
    TeamScope team;
    originalCoins(player, delta);
}
void __attribute__((fastcall)) syncResources(void* player, void*, unsigned mask) {
    // Pickups, purchases and bomb placement also write counts directly, then
    // call this native broadcast. Restore its complete co-op audience.
    const auto shared = mask & 0x5f;
    if (!enabled || !shared) {
        originalResources(player, mask);
        return;
    }
    {
        TeamScope team;
        originalResources(player, shared);
    }
    // The same native helper also broadcasts Hourglass charges and other
    // actor state. Keep those scoped to their original room audience.
    if (mask & ~0x5fu)
        originalResources(player, mask & ~0x5fu);
    for (const auto& [slot, saved] : dormant) {
        (void)slot;
        for (const auto actor : saved.actors)
            engine<CopyResources>(0x3596a0)(player, reinterpret_cast<void*>(actor), shared);
    }
}
// Native floor loading has no per-room Scope. Presentation still needs the
// local actor first, without changing the roster used by gameplay/loading.
struct ViewRoster {
    Vector saved, scratch;
    explicit ViewRoster(const std::vector<Address>& players) : saved(roster()) {
        assign(scratch, players);
        roster() = scratch;
    }
    ~ViewRoster() {
        scratch = roster();
        roster() = saved;
        release(scratch.begin, scratch.capacity - scratch.begin);
    }
};
unsigned viewDepth = 0;
struct ViewCall {
    ViewCall() {
        ++viewDepth;
    }
    ~ViewCall() {
        --viewDepth;
    }
};
using CameraSmooth = void(__attribute__((thiscall)) *)(void*, bool);
CameraSmooth originalCameraSmooth;
RoomCall originalCameraDrag;
using PlayersCenter = Vec2*(__attribute__((thiscall)) *)(void*, Vec2*, bool);
PlayersCenter originalPlayersCenter;
Vec2* __attribute__((fastcall)) playersCenter(void* manager, void*, Vec2* result, bool cached) {
    // J460 caches this globally by render frame, not by room/roster. A second
    // camera in the same frame would otherwise receive the first room's focus.
    return originalPlayersCenter(manager, result, enabled ? false : cached);
}
// Manager updates its canonical room's camera outside Game::Update. Each live
// room needs that same presentation step with its own occupants, including the
// rooms shown only on a guest. Keep the native Camera objects and smoothing.
void __attribute__((fastcall)) cameraSmooth(void* camera, void*, bool halfFrame) {
    if (!enabled || depth || transferring) {
        originalCameraSmooth(camera, halfFrame);
        return;
    }
    if (runtime::replica())
        return;
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->replicaShell || occupants(*room).empty())
            continue;
        const auto local = participant(runtime::localViewSlot());
        const auto players = occupants(*room);
        if (runtime::replica() && std::find(players.begin(), players.end(), local) == players.end())
            continue;
        Scope scope(*room, std::find(players.begin(), players.end(), local) != players.end()
                               ? controlledActors(local)
                               : players);
        const auto target = at<Address>(room->pointer, 0x11f8);
        originalCameraSmooth(reinterpret_cast<void*>(target), halfFrame);
        // Mirror Manager's one-frame focus override reset for every room.
        at<bool>(target, 0x8c) = false;
    }
}
void __attribute__((fastcall)) cameraDrag(void* camera, void*) {
    if (!enabled || depth || transferring) {
        originalCameraDrag(camera);
        return;
    }
    if (runtime::replica())
        return;
    const auto manager = *reinterpret_cast<Address*>(image + 0x87169c);
    const bool halfFrame = (at<unsigned>(manager, 0x4abbc) & 1u) != 0;
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->replicaShell || occupants(*room).empty())
            continue;
        const auto local = participant(runtime::localViewSlot());
        const auto players = occupants(*room);
        if (runtime::replica() && std::find(players.begin(), players.end(), local) == players.end())
            continue;
        Scope scope(*room, std::find(players.begin(), players.end(), local) != players.end()
                               ? controlledActors(local)
                               : players);
        const auto target = at<Address>(room->pointer, 0x11f8);
        originalCameraDrag(reinterpret_cast<void*>(target));
        if (halfFrame)
            at<bool>(target, 0x8c) = false;
    }
}
using IsCoop = bool(__attribute__((thiscall)) *)(void*);
IsCoop originalIsCoop;
bool __attribute__((fastcall)) isCoop(void* manager, void*) {
    TeamScope team;
    return originalIsCoop(manager);
}
using CoopCount = int(__attribute__((thiscall)) *)(void*);
CoopCount originalLiving, originalDead;
int __attribute__((fastcall)) living(void* manager, void*) {
    TeamScope team;
    return originalLiving(manager);
}
int __attribute__((fastcall)) dead(void* manager, void*) {
    TeamScope team;
    return originalDead(manager);
}
RoomCall originalAward;
void __attribute__((fastcall)) award(void* room, void*) {
    if (runtime::replica())
        return;
    // Loot quantity and shared loot-affecting items use the original complete
    // co-op roster; combat targeting continues to use only room occupants.
    TeamScope team;
    originalAward(room);
}
RoomCall originalReviveAll;
void __attribute__((fastcall)) reviveAll(void* manager, void*) {
    if (runtime::replica())
        return;
    // Boss completion also revives through Room::TriggerBossDeath, outside
    // the award hook. Include online ghosts in other occupied rooms there.
    TeamScope team;
    originalReviveAll(manager);
}
using Exit = void(__stdcall*)(bool);
Exit originalExit;
using End = void(__attribute__((thiscall)) *)(void*, int);
End originalEnd;
void __attribute__((fastcall)) endGame(void* target, void*, int ending) {
    if (runtime::localViewSlot() < 0 || ending < 2 || ending > 14) {
        originalEnd(target, ending);
        return;
    }
    // Native pickups/NPCs can call End while this actor's room is scoped. Keep
    // that native roster and ending semantics, then include earned progress.
    if (runtime::replica())
        return;
    const auto state = at<int>(game(), 0x26614);
    if (state < 2 || state == 6) {
        runtime::prepareEnding();
        originalEnd(target, ending);
        runtime::beginEnding(ending);
        return;
    }
    originalEnd(target, ending);
}
using Save = RoomCall;
Save originalSave;
using PostUpdate = void(__cdecl*)();
PostUpdate originalPostUpdate;
PostUpdate originalPostNewRoom;
void __cdecl postNewRoom() {
    if (enabled && active) {
        const auto head = participant(runtime::localViewSlot());
        const auto it = location.find(head);
        const auto scoped = values(roster());
        if (it == location.end() || it->second != active ||
            std::find(scoped.begin(), scoped.end(), head) == scoped.end())
            return;
    }
    originalPostNewRoom();
}
void __cdecl postUpdate() {
    if (!enabled || depth || transferring) {
        originalPostUpdate();
        return;
    }
    // Global callbacks have no actor/room argument and run once per game
    // update in vanilla. Keep their caches tied to this process's viewport;
    // native entity callbacks still execute in every authoritative room.
    const auto head = participant(runtime::localViewSlot());
    const auto it = location.find(head);
    if (it != location.end()) {
        auto players = occupants(*it->second);
        std::stable_partition(players.begin(), players.end(), [&](Address p) {
            return slotOf(p) == static_cast<unsigned>(runtime::localViewSlot());
        });
        Scope scope(*it->second, players);
        input::ViewScope inputView(runtime::localViewSlot());
        originalPostUpdate();
    }
}
void __stdcall exitGame(bool save) {
    if (enabled && depth) {
        pendingExit = save;
        return;
    }
    runtime::beforeExit(save);
    if (enabled) {
        if (save)
            for (auto& [key, room] : loaded) {
                (void)key;
                Scope scope(*room);
                originalSave(reinterpret_cast<void*>(room->pointer));
            }
        beforeStart();
    }
    originalExit(save);
    runtime::afterExit(save);
}
void restorePositions(Address room) {
    const Address list = room + 0x1258;
    const auto data = at<Address>(list, 4);
    for (unsigned i = 0; i < at<unsigned>(list, 12); ++i) {
        const auto entity = at<Address>(data, i * 4);
        if (at<bool>(entity, 0x175)) {
            at<float>(entity, 0x33c) = at<float>(entity, 0x344);
            at<float>(entity, 0x340) = at<float>(entity, 0x348);
            at<bool>(entity, 0x175) = false;
        }
    }
}
void moveEntity(Address entity, Room& from, Room& to) {
    for (std::size_t offset = 0x20; offset <= 0x90; offset += 0x10) {
        const auto list = from.pointer + 0x1218 + offset;
        auto data = reinterpret_cast<Address*>(at<Address>(list, 4));
        auto& size = at<unsigned>(list, 12);
        for (unsigned i = 0; i < size;) {
            if (data[i] != entity) {
                ++i;
                continue;
            }
            std::memmove(data + i, data + i + 1, (--size - i) * sizeof(Address));
        }
    }
    using Invalidate = void(__attribute__((thiscall))*)(void*, unsigned, unsigned, unsigned);
    engine<Invalidate>(0x1b570)(reinterpret_cast<void*>(from.pointer + 0x1218),
                                at<unsigned>(entity, 0x28), at<unsigned>(entity, 0x2c),
                                at<unsigned>(entity, 0x30));
    at<bool>(entity, 0x170) = false;
    at<unsigned>(entity, 0x20) = at<unsigned>(to.pointer, 0x1214)++;
    using Add = void(__attribute__((thiscall))*)(void*, void*);
    engine<Add>(0x18500)(reinterpret_cast<void*>(to.pointer + 0x1218),
                         reinterpret_cast<void*>(entity));
}
std::vector<Address> followers(Address player, const Room& room) {
    std::vector<Address> candidates, result;
    // J460 keeps attached knives in the persistence list along with familiars;
    // transient weapons can also occur in the ordinary list. Dark Esau is an
    // NPC in the enemy list, despite following a player across rooms. Preserve
    // native iteration order and avoid transferring an entity twice.
    for (unsigned offset : {0x30u, 0x20u, 0x40u}) {
        const auto list = room.pointer + 0x1218 + offset;
        for (unsigned i = 0; i < at<unsigned>(list, 12); ++i) {
            const auto entity = at<Address>(at<Address>(list, 4), i * 4);
            if (std::find(candidates.begin(), candidates.end(), entity) == candidates.end())
                candidates.push_back(entity);
        }
    }
    auto owned = [player](Address entity) {
        for (unsigned depth = 0; entity && depth < 8; ++depth) {
            if (entity == player)
                return true;
            if (at<unsigned>(entity, 0x28) == 3)
                return at<Address>(entity, 0x410) == player;
            entity = at<Address>(entity, 0x3bc);
        }
        return false;
    };
    std::vector<Address> jacobs;
    for (auto occupant : occupants(room))
        if (at<int>(occupant, 0x13c0) == 37 || at<int>(occupant, 0x13c0) == 39)
            jacobs.push_back(occupant);
    for (auto entity : candidates) {
        const auto type = at<unsigned>(entity, 0x28);
        bool darkEsau =
            type == 866 &&
            (at<Address>(player, 0x1fc0) == entity || owned(at<Address>(entity, 0x3bc)) ||
             owned(at<Address>(entity, 0x3c8)) || owned(at<Address>(entity, 0x3c4)));
        // Native room saves restore Dark Esau as an NPC without a spawner and
        // cannot restore a player's EntityPtr across our independent rooms.
        // Rebind only when the room has one unambiguous Tainted Jacob owner.
        if (type == 866 && !darkEsau && jacobs.size() == 1 && jacobs[0] == player &&
            !at<Address>(entity, 0x3bc) && !at<Address>(entity, 0x3c8) &&
            !at<Address>(entity, 0x3c4)) {
            using SetRef = void(__attribute__((fastcall))*)(void*, void*);
            engine<SetRef>(0x2b5b50)(reinterpret_cast<void*>(player + 0x1fc0),
                                     reinterpret_cast<void*>(entity));
            engine<SetRef>(0x2b5b50)(reinterpret_cast<void*>(entity + 0x3c8),
                                     reinterpret_cast<void*>(player));
            darkEsau = true;
        }
        if ((type == 3 && at<Address>(entity, 0x410) == player) ||
            (type == 8 &&
             (owned(at<Address>(entity, 0x3bc)) || owned(at<Address>(entity, 0x3c8)))) ||
            darkEsau)
            result.push_back(entity);
    }
    return result;
}
void place(Address entity, Vec2 position) {
    at<Vec2>(entity, 0x33c) = at<Vec2>(entity, 0x344) = position;
    at<Vec2>(entity, 0x360) = {0, 0};
    at<bool>(entity, 0x175) = false;
}
bool occupiedCombat(const Room& room, Address arriving) {
    if (room.replicaShell)
        return false;
    using IsClear = bool(__attribute__((thiscall))*)(void*);
    // J460 Room::IsClear reads its descriptor's CLEAR flag. Reuse the same
    // native predicate used by Lua, not an enemy-count approximation.
    if (engine<IsClear>(0x36080)(reinterpret_cast<void*>(room.pointer)))
        return false;
    return std::any_of(participants.begin(), participants.end(), [&](Address player) {
        const auto found = location.find(player);
        return slotOf(player) != slotOf(arriving) && (connectedMask & (1u << slotOf(player))) &&
               found != location.end() && found->second == &room;
    });
}
void arrival(Address player, const Room& room, int door, const std::vector<Address>& companions,
             bool protect) {
    if (door >= 0 && door < 8) {
        using DoorPosition = Vec2*(__attribute__((thiscall))*)(void*, Vec2*, int);
        Vec2 position;
        engine<DoorPosition>(0x3f79d0)(reinterpret_cast<void*>(room.pointer), &position, door);
        constexpr Vec2 inward[] = {{40, 0}, {0, 40}, {-40, 0}, {0, -40}};
        position.x += inward[door % 4].x;
        position.y += inward[door % 4].y;
        place(player, position);
        for (auto entity : companions)
            place(entity, position);
    }
    if (protect) {
        using Cooldown = void(__attribute__((thiscall))*)(void*, int);
        engine<Cooldown>(0x361d0)(reinterpret_cast<void*>(player), 90);
    }
}
void __attribute__((fastcall)) save(void* room, void*) {
    if (reinterpret_cast<Address>(room) != skipSave)
        originalSave(room);
}
using Change = void(__attribute__((thiscall)) *)(void*, int, int);
Change originalChange;
using Transition = void(__attribute__((thiscall)) *)(void*, int, int, int, void*, int);
Transition originalTransition;
Address actor = 0;
using PlayerUpdate = RoomCall;
PlayerUpdate originalPlayerUpdate;
void __attribute__((fastcall)) playerUpdate(void* player, void*) {
    // Native stage loading waits for player departure/arrival animations.
    // Those updates must advance while room replication is suspended.
    if (runtime::replica() && enabled && !runtime::ending()) {
        // Gameplay stays authoritative. Charge-bar overlays are local UI and
        // need the native animation update after Render changes their pose.
        using UpdateSprite = void(__attribute__((thiscall))*)(void*);
        for (unsigned i = 0; i < 7; ++i)
            engine<UpdateSprite>(0x9100)(static_cast<char*>(player) + 0x758 + i * 0x114);
        return;
    }
    const auto before = actor;
    actor = reinterpret_cast<Address>(player);
    originalPlayerUpdate(player);
    actor = before;
}
Address currentActor(void* explicitActor = nullptr) {
    if (explicitActor)
        return reinterpret_cast<Address>(explicitActor);
    if (actor)
        return actor;
    if (viewDepth)
        return participant(runtime::localViewSlot());
    if (active) {
        auto players = values(roster());
        if (players.size() == 1)
            return players.front();
    }
    return 0;
}
std::optional<Key> destination(Room& source, int index, int dimension) {
    if (!validRoomRequest(index, dimension))
        return std::nullopt;
    const auto resolve = [&]() -> std::optional<Key> {
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        const auto desc = reinterpret_cast<Address>(
            engine<Desc>(0x340bc0)(reinterpret_cast<void*>(game()), index,
                                   dimension < 0 ? source.key.dimension : dimension));
        if (!desc || !at<Address>(desc, 0x10))
            return std::nullopt;
        const auto key = canonicalRoomDestination(index, at<int>(desc, 4), at<int>(desc, 0xc));
        if (!key)
            return std::nullopt;
        return Key{(*key)[0], (*key)[1]};
    };
    if (active == &source || (index != -100 && index != -101))
        return resolve();
    // Only aliases depend on the current room. Descriptor lookup cannot
    // replace actors; avoid mutating a caller's participant iteration.
    Scope scope(source, occupants(source), false);
    return resolve();
}
bool remoteCommand(Address player, int index, int dimension, bool teleport) {
    if (player != participant(runtime::localViewSlot()))
        return false;
    const auto from = location.find(player);
    if (from == location.end())
        return false;
    const auto source = from->second->key;
    const auto target = destination(*from->second, index, dimension);
    if (!target)
        return false;
    return runtime::requestRoom(
        {static_cast<std::uint8_t>(at<int>(game(), 0)),
         static_cast<std::uint8_t>(at<int>(game(), 4)), static_cast<std::uint8_t>(source.dimension),
         static_cast<std::uint8_t>(target->dimension), static_cast<std::int16_t>(source.index),
         static_cast<std::int16_t>(target->index), teleport});
}
bool queue(Address player, int index, int dimension, int door, bool teleport = false,
           bool animateDeparture = true) {
    for (auto head : participants) {
        const auto actors = controlledActors(head);
        if (std::find(actors.begin(), actors.end(), player) != actors.end()) {
            player = head;
            break;
        }
    }
    auto it = location.find(player);
    if (!enabled || it == location.end())
        return false;
    const auto target = destination(*it->second, index, dimension);
    if (!target)
        return false;
    const auto key = *target;
    if (key == it->second->key)
        return true;
    if (std::any_of(pending.begin(), pending.end(),
                    [player](const auto& r) { return r.player == player; }))
        return true;
    pending.push_back({player, key, door, teleport, animateDeparture});
    if (teleport && animateDeparture) {
        using Animate = void(__attribute__((thiscall))*)(void*, bool);
        for (auto p : controlledActors(player))
            engine<Animate>(0x3abcc0)(reinterpret_cast<void*>(p), true);
    }
    return true;
}
void __attribute__((fastcall)) transition(void* g, void*, int index, int direction, int animation,
                                          void* player, int dimension) {
    if (!enabled || transferring) {
        originalTransition(g, index, direction, animation, player, dimension);
        return;
    }
    const auto manager = at<Address>(image, 0x87169c);
    if (!runtime::replica() && index == -10 && direction == -1 && animation == 1 && !player &&
        dimension == -1 && at<int>(game(), 0) == 13 && at<int>(game(), 4) == 1 &&
        at<bool>(manager, 0x21618) && at<int>(manager, 0x2161c) == 25) {
        pendingDogma = at<Address>(game(), 0x18300);
        return;
    }
    const auto who = currentActor(player);
    const bool teleport = animation == 3 || animation == 11 || animation == 16;
    if (runtime::replica()) {
        if (!remoteCommand(who, index, dimension, teleport))
            logger("mod_room_command=REJECTED local_actor_unresolved");
        return;
    }
    if (animation == 12 && who) {
        rewind::request(slotOf(who));
        return;
    }
    // Native item revivals (Dead Cat, Collar, Ankh, 1up) hide the actor until
    // RoomTransition::ChangeRoom restores visibility. Our per-actor transfer
    // bypasses that process-wide screen, including when the previous room is
    // already the actor's current room.
    if (animation >= 5 && animation <= 10 && who)
        pendingItemRevival.insert(slotOf(who));
    const int leave = at<int>(game(), 0x18318);
    int enter = leave >= 0 && leave < 8 ? (leave % 4 + 2) % 4 + (leave / 4) * 4 : -1;
    if (enter >= 0) {
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        const auto target = reinterpret_cast<Address>(
            engine<Desc>(0x340bc0)(reinterpret_cast<void*>(game()), index, dimension));
        if (target)
            for (int slot = 0; slot < 8; ++slot) {
                const int neighbor = at<int>(target, 0x1c + slot * 4);
                if (neighbor < 0 || neighbor >= 169 || slot % 4 != (leave % 4 + 2) % 4)
                    continue;
                const auto source = reinterpret_cast<Address>(
                    engine<Desc>(0x340bc0)(reinterpret_cast<void*>(game()), neighbor, dimension));
                if (source && at<int>(source, 4) == at<int>(game(), 0x18304)) {
                    enter = slot;
                    break;
                }
            }
    }
    // Native TELEPORT starts the actor's exit animation before changing the
    // room. Keep that sequence per actor, without the global transition that
    // would also freeze/flash players fighting in other rooms.
    // Portal effects start their native Trapdoor animation after this call.
    // Transfer at the frame boundary and apply the arrival there, rather than
    // waiting for a TeleportUp animation which the effect will overwrite.
    if (!queue(who, index, dimension, teleport ? -1 : enter, teleport, animation == 3))
        logger("room_transition=REJECTED actor_unresolved");
}
void __attribute__((fastcall)) change(void* g, void*, int index, int dimension) {
    if (!enabled || transferring) {
        originalChange(g, index, dimension);
        return;
    }
    if (runtime::replica()) {
        if (!remoteCommand(currentActor(), index, dimension, false))
            logger("mod_room_command=REJECTED local_actor_unresolved");
        return;
    }
    if (!queue(currentActor(), index, dimension, at<int>(game(), 0x1831c)))
        logger("room_change=REJECTED actor_unresolved");
}
void __attribute__((fastcall)) stageTransition(void* g, void*, bool same, int animation,
                                               void* player) {
    if (!enabled) {
        originalStage(g, same, animation, player);
        return;
    }
    if (runtime::replica())
        return;
    // A floor transaction has precedence over room transfers in the same tick.
    // The first actor in deterministic room-update order owns the transaction.
    if (!pendingStage)
        pendingStage = StageRequest{same, animation, currentActor(player)};
}
void __cdecl rKey() {
    if (!enabled) {
        originalRKey();
        return;
    }
    // J460's R Key timer calls TriggerRKey directly. Defer it until the room
    // scope is gone so its native cleanup sees the complete co-op roster.
    if (!runtime::replica())
        pendingRKey = true;
}
Room* findRoom(Address player) {
    auto it = location.find(player);
    return it == location.end() ? nullptr : it->second;
}
void canonical() {
    if (runtime::replica())
        if (auto room = findRoom(participant(runtime::localViewSlot()))) {
            room->activate();
            return;
        }
    for (auto player : participants)
        if (auto room = findRoom(player)) {
            room->activate();
            return;
        }
}
void destroy(Room& room) {
    if (sharedOwner == &room)
        selectSharedState(nullptr);
    engine<RoomCall>(0x308c10)(&room.ambush.pendingWaves);
    using AssignImage = void*(__attribute__((thiscall))*)(void*, const void*);
    const std::array<Address, 2> emptyImage{};
    for (auto& handle : room.images)
        engine<AssignImage>(0x4283d0)(&handle, &emptyImage);
    release(room.scratch.begin, room.scratch.capacity - room.scratch.begin);
    room.scratch = {};
    if (room.owned) {
        engine<RoomCall>(0x3e9ba0)(reinterpret_cast<void*>(room.pointer));
        release(room.pointer, 0x7898);
    }
}
using LuaFn = int(__cdecl*)(lua_State*);
struct API {
    void(__cdecl* pushClosure)(lua_State*, LuaFn, int);
    void(__cdecl* setField)(lua_State*, int, const char*);
    void(__cdecl* pushBoolean)(lua_State*, int);
    void(__cdecl* pushInteger)(lua_State*, long long);
    void(__cdecl* createTable)(lua_State*, int, int);
    long long(__cdecl* checkInteger)(lua_State*, int);
    const char*(__cdecl* checkString)(lua_State*, int, std::size_t*);
    const char*(__cdecl* pushString)(lua_State*, const char*, std::size_t);
    int(__cdecl* getTop)(lua_State*);
    void*(__cdecl* toUserdata)(lua_State*, int);
    void*(__cdecl* newUserdata)(lua_State*, std::size_t);
    std::size_t(__cdecl* rawLength)(lua_State*, int);
    int(__cdecl* getMetatable)(lua_State*, int);
    int(__cdecl* setMetatable)(lua_State*, int);
    void(__cdecl* rawSetI)(lua_State*, int, long long);
    void(__cdecl* pushValue)(lua_State*, int);
    int(__cdecl* pcall)(lua_State*, int, int, int, std::intptr_t, void*);
    int(__cdecl* error)(lua_State*);
} lua{};
bool adopt() {
    if (enabled || depth)
        return false;
    participants = logicalPlayers();
    if (participants.empty() || participants.size() > 4)
        return false;
    if (!originalPlayerUpdate) {
        auto update =
            reinterpret_cast<void*>(at<Address>(at<Address>(participants.front(), 0), 0xc));
        if (MH_CreateHook(update, reinterpret_cast<void*>(playerUpdate),
                          reinterpret_cast<void**>(&originalPlayerUpdate)) != MH_OK ||
            MH_EnableHook(update) != MH_OK)
            return false;
    }
    auto room = std::make_unique<Room>();
    room->pointer = at<Address>(game(), 0x18300);
    room->owned = true;
    room->key = {at<int>(game(), 0x1830c), at<int>(game(), 0x18304)};
    room->capture();
    sharedOwner = room.get(); // Adopt the state already owned by the native game.
    for (auto player : values(roster()))
        location[player] = room.get();
    loaded.emplace(room->key, std::move(room));
    enabled = true;
    logger("rooms=ENABLED players=" + std::to_string(participants.size()));
    return true;
}
int enable(lua_State* L) {
    lua.pushBoolean(L, adopt());
    return 1;
}
int request(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const int index = static_cast<int>(lua.checkInteger(L, 2));
    const int dimension = static_cast<int>(lua.checkInteger(L, 3));
    const int door = static_cast<int>(lua.checkInteger(L, 4));
    lua.pushBoolean(L, slot >= 0 && slot < 4 && participant(slot) &&
                           queue(participant(slot), index, dimension, door));
    return 1;
}
int withPlayer(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    Room* room = slot >= 0 && slot < 4 ? findRoom(participant(slot)) : nullptr;
    if (depth || (!room && (enabled || slot < 0 ||
                            static_cast<unsigned>(slot) >= values(roster()).size()))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    int result;
    if (room) {
        const bool actorOnly = lua.getTop(L) > 2 && lua.checkInteger(L, 3) != 0;
        Scope scope(*room, actorOnly ? controlledActors(participant(slot)) : occupants(*room));
        lua.pushValue(L, 2);
        result = lua.pcall(L, 0, 0, 0, 0, nullptr);
    } else {
        lua.pushValue(L, 2);
        result = lua.pcall(L, 0, 0, 0, 0, nullptr);
    }
    if (result)
        return lua.error(L);
    lua.pushBoolean(L, true);
    return 1;
}
int withLocalView(lua_State* L) {
    int result = 0;
    withView(
        [&] {
            lua.pushValue(L, 1);
            result = lua.pcall(L, 0, 0, 0, 0, nullptr);
        },
        true);
    if (result)
        return lua.error(L);
    lua.pushBoolean(L, true);
    return 1;
}
int integrationMove(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1), index = lua.checkInteger(L, 2),
               dimension = lua.checkInteger(L, 3);
    lua.pushBoolean(L, !runtime::replica() && slot >= 0 && slot < 4 && participant(slot) &&
                           (connectedMask & (1u << slot)) && index >= -20 && index < 169 &&
                           dimension >= 0 && dimension <= 2 &&
                           queue(participant(slot), index, dimension, -1, true));
    return 1;
}
int cancelIntegrationMove(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1), index = lua.checkInteger(L, 2),
               dimension = lua.checkInteger(L, 3);
    if (!runtime::replica() && slot >= 0 && slot < 4) {
        const auto head = participant(slot);
        std::erase_if(pending, [&](const auto& request) {
            return request.player == head && request.destination.index == index &&
                   request.destination.dimension == dimension;
        });
    }
    return 0;
}
int actorIdentities(lua_State* L) {
    // The borrowed canonical roster remains available inside nested UI scopes.
    const auto all = values(teamRoster ? *teamRoster : roster());
    lua.createTable(L, static_cast<int>(all.size()), 0);
    unsigned entry = 0;
    for (unsigned owner = 0; owner < 4; ++owner) {
        const auto head = participant(owner);
        if (!head)
            continue;
        std::vector<Address> actors{head};
        for (auto actor : all)
            if (actor != head &&
                (at<int>(actor, 0x1618) == static_cast<int>(owner + 1) ||
                 at<Address>(head, 0x1e68) == actor || at<Address>(actor, 0x1e68) == head))
                actors.push_back(actor);
        for (unsigned role = 0; role < actors.size(); ++role) {
            lua.createTable(L, 0, 3);
            lua.pushInteger(L, std::find(all.begin(), all.end(), actors[role]) - all.begin());
            lua.setField(L, -2, "index");
            lua.pushInteger(L, owner + 1);
            lua.setField(L, -2, "owner");
            lua.pushInteger(L, role + 1);
            lua.setField(L, -2, "role");
            lua.rawSetI(L, -2, ++entry);
        }
    }
    return 1;
}
int withOwner(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const auto head = slot >= 0 && slot < 4 ? participant(slot) : 0;
    const auto room = head ? findRoom(head) : nullptr;
    if (runtime::replica() || depth || !room || !(connectedMask & (1u << slot))) {
        lua.pushBoolean(L, false);
        return 1;
    }
    int result;
    {
        Scope scope(*room, controlledActors(head));
        lua.pushValue(L, 2);
        result = lua.pcall(L, 0, 0, 0, 0, nullptr);
    }
    if (result)
        return lua.error(L);
    lua.pushBoolean(L, true);
    return 1;
}
int positions(lua_State* L) {
    const auto players = enabled ? participants : logicalPlayers();
    lua.createTable(L, 0, static_cast<int>(players.size()));
    for (unsigned slot = 0; slot < players.size(); ++slot) {
        auto room = findRoom(players[slot]);
        if (room || !enabled) {
            lua.createTable(L, 0, 4);
            auto integer = [&](const char* key, long long value) {
                lua.pushInteger(L, value);
                lua.setField(L, -2, key);
            };
            integer("index", room ? room->key.index : at<int>(game(), 0x18304));
            integer("dimension", room ? room->key.dimension : at<int>(game(), 0x1830c));
            integer("updates", room ? room->updates : 0);
            integer("halves", room ? room->halves : 0);
            lua.setField(L, -2, std::to_string(slotOf(players[slot], slot)).c_str());
        }
    }
    return 1;
}
int ready(lua_State* L) {
    lua.pushBoolean(L, enabled && !resumeStage && !pendingStage && !pendingRKey);
    return 1;
}
int beginRKey(lua_State* L) {
    const bool ready = runtime::replica() && enabled && !depth;
    if (ready)
        pendingRKey = true;
    lua.pushBoolean(L, ready);
    return 1;
}
int beginCinematic(lua_State* L) {
    const bool ready = runtime::replica() && enabled && !depth && at<int>(game(), 0) == 13 &&
                       at<int>(game(), 4) == 1;
    if (ready)
        pendingDogma = at<Address>(game(), 0x18300);
    lua.pushBoolean(L, ready);
    return 1;
}
int beginFloor(lua_State* L) {
    const auto same = lua.checkInteger(L, 1), animation = lua.checkInteger(L, 2);
    const auto head = participant(runtime::localViewSlot());
    const bool ready = runtime::replica() && enabled && !depth && head &&
                       (same == 0 || same == 1) && animation >= 0 && animation <= 6;
    if (ready && !pendingStage) {
        pendingStage = StageRequest{same != 0, static_cast<int>(animation), head};
    }
    lua.pushBoolean(L, ready);
    return 1;
}
int setConnections(lua_State* L) {
    const auto mask = lua.checkInteger(L, 1);
    if (mask < 1 || mask > 15 || !(mask & 1)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    setConnected(static_cast<unsigned>(mask));
    lua.pushBoolean(L, true);
    return 1;
}
int connections(lua_State* L) {
    lua.pushInteger(L, connectedMask);
    return 1;
}
int heads(lua_State* L) {
    const bool restoredOrder = lua.getTop(L) > 0 && lua.checkInteger(L, 1) != 0;
    const auto all = values(roster()), players = logicalPlayers(!restoredOrder);
    lua.createTable(L, 0, static_cast<int>(players.size()));
    for (unsigned slot = 0; slot < players.size(); ++slot) {
        lua.pushInteger(L, std::find(all.begin(), all.end(), players[slot]) - all.begin());
        lua.setField(L, -2,
                     std::to_string(restoredOrder ? slot : slotOf(players[slot], slot)).c_str());
    }
    return 1;
}
void projectRemote(unsigned slot, const SavedLocation& p) {
    const auto head = participant(slot);
    Key key{p.dimension, p.index};
    auto found = loaded.find(key);
    if (found == loaded.end()) {
        auto room = std::make_unique<Room>();
        room->key = key;
        room->owned = true;
        room->replicaShell = true;
        room->pointer = reinterpret_cast<Address>(allocate(0x7898));
        engine<RoomCall>(0x3e9400)(reinterpret_cast<void*>(room->pointer));
        found = loaded.emplace(key, std::move(room)).first;
    }
    auto from = findRoom(head);
    auto to = found->second.get();
    if (from != to)
        for (auto actor : controlledActors(head)) {
            if (from) {
                for (auto entity : followers(actor, *from))
                    moveEntity(entity, *from, *to);
                moveEntity(actor, *from, *to);
            }
            location[actor] = to;
        }
}
int syncLocations(lua_State* L) {
    std::size_t size = 0;
    const auto bytes = lua.checkString(L, 1, &size);
    try {
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto mask = r.u8(), count = r.u8();
        if (!runtime::replica() || count > 4 || !(mask & 1) || mask > 15)
            throw std::runtime_error("Invalid replica roster");
        setConnected(mask);
        std::vector<std::pair<unsigned, SavedLocation>> values;
        for (unsigned i = 0; i < count; ++i) {
            const auto slot = r.u8();
            SavedLocation p{static_cast<int>(r.u32()), static_cast<int>(r.u32()),
                            std::bit_cast<float>(r.u32()), std::bit_cast<float>(r.u32())};
            if (slot >= 4 || !(mask & (1u << slot)) || p.dimension < 0 || p.dimension > 2 ||
                p.index < -20 || p.index >= 169 || !std::isfinite(p.x) || !std::isfinite(p.y))
                throw std::runtime_error("Invalid authoritative player location");
            const auto actor = participant(slot);
            if (!actor)
                throw std::runtime_error("Replica player missing");
            const auto room = findRoom(actor);
            if (slot == static_cast<unsigned>(runtime::localViewSlot()) &&
                (!room || room->key.index != p.index || room->key.dimension != p.dimension)) {
                if (!queue(actor, p.index, p.dimension, -1))
                    throw std::runtime_error("Replica room transfer failed");
            }
            values.emplace_back(slot, p);
        }
        r.finish();
        finishFrame();
        for (const auto& [slot, p] : values) {
            const auto head = participant(slot);
            if (slot != static_cast<unsigned>(runtime::localViewSlot()))
                projectRemote(slot, p);
            place(head, {p.x, p.y});
        }
        canonical();
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
// Replica room initialization uses an explicit layout from the authority.
// Special rooms are created lazily by gameplay (Devil/Angel, Error, etc.);
// generating the floor from the same seed does not create these descriptors.
// No process pointers, STL containers or spawn configuration cross the wire.
std::map<Key, std::array<std::uint8_t, 0x5c>> replicaLayouts;
// The native minimap reads saved entities, which replicas never simulate or
// save. Supply pickup metadata only while caching the map; room loading and
// saving must retain their original owned vectors.
using MapEntity = std::array<std::uint32_t, 0x78 / 4>;
std::map<Key, std::vector<MapEntity>> replicaMapEntities;
constexpr std::array<unsigned, 6> mapFields{0, 4, 8, 0x14, 0x28, 0x2c};
int mapPickups(lua_State* L) {
    try {
        if (lua.getTop(L) == 2) {
            const int index = lua.checkInteger(L, 1), dimension = lua.checkInteger(L, 2);
            using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
            const auto desc = reinterpret_cast<Address>(
                engine<Desc>(0x340bc0)(reinterpret_cast<void*>(game()), index, dimension));
            if (!desc)
                throw std::runtime_error("Map descriptor is unavailable");
            lan::Writer w(lan::Message::world);
            w.u32(dimension);
            w.u32(index);
            const auto received = replicaMapEntities.find({dimension, index});
            if (runtime::replica() && received != replicaMapEntities.end()) {
                for (const auto& entity : received->second)
                    for (auto offset : mapFields)
                        w.u32(entity[offset / 4]);
            } else {
                const auto saved = at<Vector>(desc, 0x74);
                for (auto entity = saved.begin; entity < saved.end; entity += 0x78)
                    if (at<unsigned>(entity, 0) == 5 || at<unsigned>(entity, 0) == 6)
                        for (auto offset : mapFields)
                            w.u32(at<unsigned>(entity, offset));
            }
            lua.pushString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                           w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas receive map pickups");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 1, &size);
        if (size < 8 || (size - 8) % 24 || size > 8 + 4096 * 24)
            throw std::runtime_error("Invalid map pickups");
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        Key key{static_cast<int>(r.u32()), static_cast<int>(r.u32())};
        if (key.dimension < 0 || key.dimension > 2 || key.index < -20 || key.index >= 169)
            throw std::runtime_error("Invalid map room");
        std::vector<MapEntity> entities((size - 8) / 24);
        for (auto& entity : entities) {
            for (auto offset : mapFields)
                entity[offset / 4] = r.u32();
            if (entity[0] != 5 && entity[0] != 6)
                throw std::runtime_error("Invalid map entity");
        }
        r.finish();
        auto& previous = replicaMapEntities[key];
        const bool changed = previous != entities;
        previous = std::move(entities);
        lua.pushBoolean(L, true);
        lua.pushBoolean(L, changed);
        return 2;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int roomLayout(lua_State* L) {
    try {
        if (lua.getTop(L) == 0 || lua.getTop(L) == 2) {
            using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
            const int dimension = lua.getTop(L) ? lua.checkInteger(L, 2) : at<int>(game(), 0x1830c);
            const int index = lua.getTop(L) ? lua.checkInteger(L, 1) : at<int>(game(), 0x18304);
            const auto desc =
                lua.getTop(L)
                    ? reinterpret_cast<Address>(engine<Desc>(0x340bc0)(
                          reinterpret_cast<void*>(game()), lua.checkInteger(L, 1), dimension))
                    : at<Address>(at<Address>(game(), 0x18300), 4);
            const auto override = at<Address>(desc, 0x14);
            const auto config = override ? override : at<Address>(desc, 0x10);
            lan::Writer w(lan::Message::world);
            w.u32(dimension);
            w.u32(index < 0 ? index : at<int>(desc, 4));
            w.u32(at<int>(desc, 0));
            w.u32(at<int>(desc, 8));
            // Large rooms occupy several cells; the minimap uses this native
            // cell-to-descriptor table rather than GetRoomByIdx's fallback.
            std::vector<unsigned> cells;
            if (index >= 0)
                for (unsigned cell = 0; cell < 169; ++cell)
                    if (at<int>(game(), 0x17adc + (dimension * 169 + cell) * 4) == at<int>(desc, 8))
                        cells.push_back(cell);
            w.u8(cells.size());
            for (auto cell : cells)
                w.u8(cell);
            for (auto offset : {0u, 4u, 8u, 12u, 16u, 0x2cu, 0x38u, 0x3cu, 0x48u, 0x4cu})
                w.u32(at<unsigned>(config, offset));
            w.u8(at<unsigned char>(config, 0x46));
            w.u8(at<unsigned char>(config, 0x47));
            w.u32(at<unsigned>(desc, 0x18));
            for (unsigned offset = 0x1c; offset < 0x3c; offset += 4)
                w.u32(at<unsigned>(desc, offset));
            for (unsigned offset = 0x58; offset <= 0x64; offset += 4)
                w.u32(at<unsigned>(desc, offset));
            lua.pushString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                           w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas receive room layouts");
        std::size_t size;
        const auto data = lua.checkString(L, 1, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(data), size});
        Key key{static_cast<int>(r.u32()), static_cast<int>(r.u32())};
        const int gridIndex = r.u32(), listIndex = r.u32();
        std::vector<unsigned> cells(r.u8());
        for (auto& cell : cells)
            cell = r.u8();
        std::array<std::uint8_t, 0x5c> config{};
        auto address = reinterpret_cast<Address>(config.data());
        for (auto offset : {0u, 4u, 8u, 12u, 16u, 0x2cu, 0x38u, 0x3cu, 0x48u, 0x4cu})
            at<unsigned>(address, offset) = r.u32();
        at<unsigned char>(address, 0x46) = r.u8();
        at<unsigned char>(address, 0x47) = r.u8();
        // An empty native MSVC small string and no initial spawns. Entity and
        // grid state is installed by the authoritative snapshot after Init.
        at<unsigned>(address, 0x28) = 15;
        const auto allowed = r.u32();
        std::array<unsigned, 8> doors{};
        for (auto& door : doors)
            door = r.u32();
        std::array<unsigned, 4> seeds{};
        for (auto& seed : seeds)
            seed = r.u32();
        r.finish();
        if (key.dimension < 0 || key.dimension > 2 || key.index < -20 || key.index >= 169 ||
            gridIndex < -20 || gridIndex >= 169 || listIndex < (key.index < 0 ? -1 : 0) ||
            listIndex >= (key.index < 0 ? 527 : 507) ||
            (key.index >= 0 && std::find(cells.begin(), cells.end(), key.index) == cells.end()) ||
            std::any_of(cells.begin(), cells.end(), [](auto cell) { return cell >= 169; }) ||
            at<unsigned>(address, 0x48) < 1 || at<unsigned>(address, 0x48) > 12 ||
            at<unsigned>(address, 8) < 1 || at<unsigned>(address, 8) > 32 ||
            !at<unsigned char>(address, 0x46) || at<unsigned char>(address, 0x46) > 26 ||
            !at<unsigned char>(address, 0x47) || at<unsigned char>(address, 0x47) > 14)
            throw std::runtime_error(
                "Invalid authoritative room layout dimension=" + std::to_string(key.dimension) +
                " index=" + std::to_string(key.index) + " grid=" + std::to_string(gridIndex) +
                " list=" + std::to_string(listIndex));
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        // All floor descriptors are constructed by the game at startup. A new
        // red room has no replica index yet: GetRoomByIdx returns a shared
        // sentinel in that case, which must never be populated as a real room.
        const auto desc = key.index >= 0
                              ? game() + 0x14 + listIndex * 0xb8
                              : reinterpret_cast<Address>(engine<Desc>(0x340bc0)(
                                    reinterpret_cast<void*>(game()), key.index, key.dimension));
        if (!desc)
            throw std::runtime_error("Replica descriptor is unavailable");
        {
            auto& stored = replicaLayouts[key];
            stored = config;
            at<Address>(desc, 0x10) = reinterpret_cast<Address>(stored.data());
            at<Address>(desc, 0x14) = 0;
            at<int>(desc, 0) = gridIndex;
            at<int>(desc, 4) = key.index;
            at<int>(desc, 8) = listIndex;
            at<int>(desc, 0xc) = key.dimension;
            if (key.index >= 0) {
                registerMapRoom(std::span<int, 507>(reinterpret_cast<int*>(game() + 0x17adc), 507),
                                at<unsigned>(game(), 0x182cc), key.dimension, key.index, listIndex,
                                cells);
            }
            at<unsigned>(desc, 0x18) = allowed;
            for (unsigned i = 0; i < doors.size(); ++i)
                at<unsigned>(desc, 0x1c + 4 * i) = doors[i];
            for (unsigned i = 0; i < seeds.size(); ++i)
                at<unsigned>(desc, 0x58 + 4 * i) = seeds[i];
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int stateClock(lua_State* L) {
    if (runtime::replica())
        at<unsigned>(game(), 0x264f8) = static_cast<unsigned>(lua.checkInteger(L, 1));
    return 0;
}
int refreshMap(lua_State* L) {
    if (!runtime::replica()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    // J460 Game::UpdateVisibility ends by refreshing these two map caches.
    // Use that display-only step after applying authoritative DisplayFlags;
    // its preceding door walk would recompute visibility from replica doors.
    const auto g = game();
    for (auto offset : {0x25ee4u, 0x26044u})
        engine<RoomCall>(0x58b5e0)(reinterpret_cast<void*>(g + offset));
    if (at<int>(g, 0x22ed4) != 2) {
        at<int>(g, 0x22ed4) = 1;
        at<int>(g, 0x22edc) = 2;
    }
    lua.pushBoolean(L, true);
    return 1;
}
int actorSprites(lua_State* L) {
    const auto index = lua.checkInteger(L, 1);
    const auto all = values(roster());
    auto sample = static_cast<Address*>(lua.toUserdata(L, 2));
    if (index < 0 || static_cast<std::size_t>(index) >= all.size() || !sample ||
        lua.rawLength(L, 2) != 8 || sample[1] != all[index] + 0x48) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto player = all[index];
    const auto costumes = at<Vector>(player, 0x1220);
    if (costumes.end < costumes.begin || (costumes.end - costumes.begin) % 0x130 ||
        costumes.end - costumes.begin > 0x130 * 4096) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lua.createTable(L, 10 + (costumes.end - costumes.begin) / 0x130, 0);
    unsigned ordinal = 1;
    auto push = [&](Address sprite) {
        // Clone the game's non-owning LuaBridge Sprite wrapper, retaining its
        // native metatable/destructor. The ANM2 remains owned by the player.
        auto wrapper = static_cast<Address*>(lua.newUserdata(L, 8));
        wrapper[0] = sample[0];
        wrapper[1] = sprite;
        lua.getMetatable(L, 2);
        lua.setMetatable(L, -2);
        lua.rawSetI(L, -2, ordinal++);
    };
    for (auto offset : {0x41cu, 0xff8u, 0xee4u})
        push(player + offset);
    // The seven native charge-bar sprites advance in Player::Update, which
    // replicas suppress. Their charged/flash overlays must follow the host.
    for (unsigned i = 0; i < 7; ++i)
        push(player + 0x758 + i * 0x114);
    for (auto address = costumes.begin; address < costumes.end; address += 0x130)
        push(address);
    return 1;
}
int actorForm(lua_State* L) {
    const auto index = lua.checkInteger(L, 1), desired = lua.checkInteger(L, 2);
    const auto controller = lua.getTop(L) >= 3 ? lua.checkInteger(L, 3) : -1;
    const auto all = values(roster());
    if (!runtime::replica() || !enabled || depth || index < 0 ||
        static_cast<std::size_t>(index) > all.size() || (desired != 29 && desired != 38)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (static_cast<std::size_t>(index) == all.size()) {
        // Native Player's Birthright update promotes its existing raw backup
        // into a listed twin. Replicas skip gameplay Update, so restore that
        // ownership only when the authority actually includes the extra body.
        for (auto owner : all) {
            const auto kind = at<int>(owner, 0x13c0);
            const auto backup = at<Address>(owner, 0x1e6c);
            auto room = findRoom(owner);
            if ((kind != 29 && kind != 38) || at<int>(owner, 0x1618) != controller || !room ||
                !backup || at<unsigned>(backup, 0x28) != 1 || at<int>(backup, 0x13c0) != desired ||
                at<Address>(backup, 0x1e6c) != owner ||
                std::find(all.begin(), all.end(), backup) != all.end())
                continue;
            using AssignPtr = void*(__attribute__((thiscall))*)(void*, void*);
            using AddPlayer = void(__attribute__((thiscall))*)(void*, void*);
            {
                Scope scope(*room, all);
                engine<AssignPtr>(0xcf1d0)(reinterpret_cast<void*>(owner + 0x1e68),
                                           reinterpret_cast<void*>(backup));
                engine<AssignPtr>(0xcf1d0)(reinterpret_cast<void*>(backup + 0x1e68),
                                           reinterpret_cast<void*>(owner));
                at<Address>(owner, 0x1e6c) = at<Address>(backup, 0x1e6c) = 0;
                at<int>(backup, 0x1618) = controller;
                at<bool>(backup, 0x170) = at<bool>(backup, 0x172) = true;
                at<Vec2>(backup, 0x33c) = at<Vec2>(owner, 0x33c);
                engine<AddPlayer>(0x5b9f60)(reinterpret_cast<void*>(game() + 0x1baa8),
                                            reinterpret_cast<void*>(backup));
            }
            participants = logicalPlayers();
            logger("actor_form=LISTED index=" + std::to_string(index) +
                   " type=" + std::to_string(desired));
            lua.pushBoolean(L, true);
            return 1;
        }
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto old = all[index];
    if (controller >= 0 && at<int>(old, 0x1618) != controller) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto kind = at<int>(old, 0x13c0);
    if (kind == desired) {
        lua.pushBoolean(L, true);
        return 1;
    }
    auto room = findRoom(old);
    if (!room || (kind != 29 && kind != 38)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    Address replacement = 0;
    for (auto offset : {0x1e68u, 0x1e6cu}) {
        const auto candidate = at<Address>(old, offset);
        if (candidate && at<unsigned>(candidate, 0x28) == 1 &&
            at<int>(candidate, 0x13c0) == desired) {
            replacement = candidate;
            break;
        }
    }
    if (!replacement) {
        lua.pushBoolean(L, false);
        return 1;
    }
    using Replace = bool(__attribute__((thiscall))*)(void*, void*, void*);
    bool replaced;
    {
        // Birthright's two listed bodies use their global native roster indices.
        // Keep that complete roster while selecting only this actor's room.
        Scope scope(*room, all);
        replaced = engine<Replace>(0x5bee80)(reinterpret_cast<void*>(game() + 0x1baa8),
                                             reinterpret_cast<void*>(old),
                                             reinterpret_cast<void*>(replacement));
    }
    participants = logicalPlayers();
    const auto current = values(roster());
    const bool ready = replaced && static_cast<std::size_t>(index) < current.size() &&
                       at<int>(current[index], 0x13c0) == desired;
    if (ready)
        logger("actor_form=REPLACED index=" + std::to_string(index) +
               " type=" + std::to_string(desired));
    lua.pushBoolean(L, ready);
    return 1;
}
int actorPoop(lua_State* L) {
    auto sprite = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!runtime::replica() || !sprite || lua.rawLength(L, 1) != 8 || sprite[1] < 0x48 ||
        at<unsigned>(sprite[1] - 0x48, 0x28) != 1 || at<int>(sprite[1] - 0x48, 0x13c0) != 25) {
        lua.pushBoolean(L, false);
        return 1;
    }
    try {
        std::size_t size;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto value = actors::readPoopState(reader);
        const auto player = sprite[1] - 0x48;
        at<int>(player, 0x1f54) = value.mana;
        for (unsigned i = 0; i < value.queue.size(); ++i)
            at<std::uint8_t>(player, 0x1f58 + i) = value.queue[i];
        lua.pushBoolean(L, true);
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int actorGhost(lua_State* L) {
    const auto index = lua.checkInteger(L, 1), ghost = lua.checkInteger(L, 2);
    const auto all = values(roster());
    wchar_t labRoot[1024];
    const auto length = GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", labRoot, 1024);
    const bool lab = length && length < 1024 &&
                     GetFileAttributesW((std::wstring(labRoot) + L"\\.isaac-lan-lab").c_str()) !=
                         INVALID_FILE_ATTRIBUTES;
    if ((!runtime::replica() && !lab) || index < 0 ||
        static_cast<std::size_t>(index) >= all.size() || (ghost != 0 && ghost != 1)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto room = findRoom(all[index]);
    if (!room) {
        lua.pushBoolean(L, false);
        return 1;
    }
    {
        // Ghost conversion removes familiars and can drop items. A remote
        // actor must never execute those effects in the displayed local room.
        Scope scope(*room, controlledActors(all[index]));
        engine<RoomCall>(ghost ? 0x3d96f0 : 0x3d93b0)(reinterpret_cast<void*>(all[index]));
    }
    lua.pushBoolean(L, true);
    return 1;
}
int laserPath(lua_State* L) {
    auto sprite = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!sprite || lua.rawLength(L, 1) != 8 || sprite[1] < 0x48 ||
        at<unsigned>(sprite[1] - 0x48, 0x28) != 7) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto entity = sprite[1] - 0x48;
    constexpr std::array<unsigned, 6> floats = {0x468, 0x46c, 0x470, 0x474, 0x478, 0x4e0};
    try {
        if (lua.getTop(L) == 1) {
            lan::Writer bytes(lan::Message::world);
            bytes.u8(at<std::uint8_t>(entity, 0x45d));
            for (auto offset : floats)
                bytes.u32(at<std::uint32_t>(entity, offset));
            bytes.u32(at<unsigned>(entity, 0x47c));
            for (auto offset : {0x480u, 0x48cu}) {
                const auto points = at<Vector>(entity, offset);
                if (points.end < points.begin || points.end > points.capacity ||
                    (points.end - points.begin) % 8 || points.end - points.begin > 2048 * 8)
                    throw std::runtime_error("Invalid native laser path");
                bytes.u16((points.end - points.begin) / 8);
                for (auto p = points.begin; p < points.end; p += 4)
                    bytes.u32(at<std::uint32_t>(p, 0));
            }
            lua.pushString(L, reinterpret_cast<const char*>(bytes.bytes.data() + 1),
                           bytes.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica()) {
            lua.pushBoolean(L, false);
            return 1;
        }
        std::size_t size = 0;
        const auto data = lua.checkString(L, 2, &size);
        lan::Reader bytes({reinterpret_cast<const std::uint8_t*>(data), size});
        const auto path = presentation::readLaserPath(bytes);
        at<std::uint8_t>(entity, 0x45d) = path.sampleState;
        for (unsigned i = 0; i < floats.size(); ++i)
            at<std::uint32_t>(entity, floats[i]) = path.values[i];
        at<unsigned>(entity, 0x47c) = path.samples;
        assign(at<Vector>(entity, 0x480), path.paths[0]);
        assign(at<Vector>(entity, 0x48c), path.paths[1]);
        lua.pushBoolean(L, true);
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
std::map<Address, RoomCall> entityUpdates;
RoomCall originalNeedleVisual = nullptr;
void __attribute__((fastcall)) needleVisual(void* npc, void*) {
    // Needle positions its body layers from native movement history during
    // Render. Replicas receive those layer poses and have no simulated trail.
    if (!runtime::replica())
        originalNeedleVisual(npc);
}
RoomCall originalDoorUpdate = nullptr;
void __attribute__((fastcall)) doorUpdate(void* door, void*) {
    // Replica doors receive their complete state and animation from the host.
    // Running native door decisions here can immediately undo a locked door.
    if (!runtime::replica())
        originalDoorUpdate(door);
}
RoomCall originalTrapdoorUpdate = nullptr;
void __attribute__((fastcall)) trapdoorUpdate(void* trapdoor, void*) {
    if (runtime::replica())
        return;
    const auto room = at<Address>(game(), 0x18300);
    using IsClear = bool(__attribute__((thiscall))*)(void*);
    if (enabled && at<int>(room, 8) == 5 &&
        !engine<IsClear>(0x36080)(reinterpret_cast<void*>(room))) {
        // Native trapdoors reopen from state zero when nobody stands nearby.
        // Keep the boss exit closed throughout combat, then let its normal
        // update open it and perform the floor transition after the clear.
        const auto grid = reinterpret_cast<Address>(trapdoor);
        at<int>(grid, 0xc) = 0;
        using Play = void(__attribute__((thiscall))*)(void*, const char*, bool);
        engine<Play>(0x0a380)(reinterpret_cast<void*>(grid + 0x40), "Closed", false);
        return;
    }
    originalTrapdoorUpdate(trapdoor);
}
void __attribute__((fastcall)) replicaEntityUpdate(void* entity, void*) {
    if (runtime::replica())
        return;
    const auto entry = at<Address>(at<Address>(reinterpret_cast<Address>(entity), 0), 0xc);
    entityUpdates.at(entry)(entity);
}
void interceptReplicaEntities(Room& room) {
    // Preserve room cleanup, doors and background updates, while the server
    // owns entity gameplay. Native containers and allocation remain untouched.
    for (std::size_t offset : {0x20u, 0x40u, 0x70u}) {
        const auto list = room.pointer + 0x1218 + offset;
        const auto data = at<Address>(list, 4), count = at<unsigned>(list, 12);
        for (unsigned i = 0; i < count; ++i) {
            const auto entity = at<Address>(data, i * 4);
            if (at<unsigned>(entity, 0x28) == 1)
                continue;
            const auto entry = at<Address>(at<Address>(entity, 0), 0xc);
            if (entityUpdates.contains(entry))
                continue;
            RoomCall original = nullptr;
            if (MH_CreateHook(reinterpret_cast<void*>(entry),
                              reinterpret_cast<void*>(replicaEntityUpdate),
                              reinterpret_cast<void**>(&original)) != MH_OK ||
                MH_EnableHook(reinterpret_cast<void*>(entry)) != MH_OK) {
                runtime::abort("Cannot isolate replica entity updates");
                return;
            }
            entityUpdates.emplace(entry, original);
        }
    }
}
} // namespace

bool update(void*, RoomCall original) {
    if (!enabled || depth || transferring)
        return false;
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->replicaShell || occupants(*room).empty())
            continue;
        if (runtime::replica()) {
            const auto players = occupants(*room);
            if (std::find(players.begin(), players.end(), participant(runtime::localViewSlot())) ==
                players.end())
                continue;
        }
        Scope scope(*room);
        if (!runtime::replica() && presentation::roomPaused())
            continue;
        restorePositions(room->pointer);
        // Game::Update decrements this before Room::Update, outside our room
        // scopes. Each room restores its own value here, so advance it once
        // for every authoritative room. Delirium's death sequence waits for
        // this timer to reach zero before spawning the completion chest.
        auto& flash = at<int>(game(), 0x26538);
        if (!runtime::replica() && flash > 0)
            --flash;
        if (at<bool>(game(), 0x676b4)) {
            using Lerp = void(__attribute__((thiscall))*)(void*, const void*, const void*);
            engine<Lerp>(0x2ef410)(reinterpret_cast<void*>(game() + 0x676b8),
                                   reinterpret_cast<void*>(game() + 0x676d0),
                                   reinterpret_cast<void*>(game() + 0x676e8));
        }
        if (runtime::replica())
            interceptReplicaEntities(*room);
        original(reinterpret_cast<void*>(room->pointer));
        ++room->updates;
    }
    return true;
}
bool half(void (*original)()) {
    if (!enabled || depth || transferring)
        return false;
    if (runtime::replica() && !runtime::ending())
        return true;
    presentation::IntroSimulationScope intro;
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->replicaShell || occupants(*room).empty())
            continue;
        Scope scope(*room);
        if (presentation::roomPaused())
            continue;
        original();
        ++room->halves;
    }
    return true;
}
bool render(void* g, RoomCall original, int slot) {
    if (!enabled || depth || slot < 0 || slot >= 4)
        return false;
    auto room = findRoom(participant(slot));
    if (!room)
        return false;
    withView([&] {
        audio::present();
        original(g);
    });
    return true;
}
void presentCamera() {
    if (!enabled || depth || transferring || !runtime::replica())
        return;
    const auto head = participant(runtime::localViewSlot());
    const auto room = findRoom(head);
    if (!room || room->replicaShell)
        return;
    const auto manager = at<Address>(image, 0x87169c);
    const bool halfFrame = (at<unsigned>(manager, 0x4abbc) & 1u) != 0;
    // Replica packets restore authority positions before prediction. Advance
    // the native camera only after the visible local position is reconciled.
    Scope scope(*room, controlledActors(head));
    auto camera = reinterpret_cast<void*>(at<Address>(room->pointer, 0x11f8));
    originalCameraSmooth(camera, halfFrame);
    at<bool>(reinterpret_cast<Address>(camera), 0x8c) = false;
    originalCameraDrag(camera);
}
bool backgroundLoading() {
    if (!enabled || !transferring || !active)
        return false;
    const auto it = location.find(participant(runtime::localViewSlot()));
    return it == location.end() || it->second != active;
}
void withView(const std::function<void()>& draw, bool localPlayersOnly) {
    const int slot = runtime::localViewSlot();
    if (slot < 0 || slot >= 4) {
        draw();
        return;
    }
    ViewCall call;
    const auto head = enabled && !transferring ? participant(slot) : 0;
    const auto room = head ? findRoom(head) : nullptr;
    auto players = values(teamRoster ? *teamRoster : roster());
    if (localPlayersOnly)
        std::erase_if(players, [&](Address p) { return at<int>(p, 0x1618) != slot + 1; });
    std::stable_partition(players.begin(), players.end(),
                          [&](Address p) { return at<int>(p, 0x1618) == slot + 1; });
    if (!room) {
        ViewRoster view(players);
        draw();
        return;
    }
    Scope scope(*room, players, false);
    draw();
}
bool checkpointReady() {
    return enabled && !depth && !resumeStage && !pendingStage && !pendingRKey && loaded.size() == 1;
}
bool stateReady() {
    return enabled && !depth && !resumeStage && !pendingStage && !pendingRKey;
}
bool viewReady() {
    return enabled && !transferring && !resumeStage && !pendingStage && !pendingRKey;
}
bool virtualized() {
    return enabled;
}
bool withCheckpointRoster(const std::function<void()>& capture) {
    if (!stateReady() || runtime::replica())
        return false;
    // Store occupied rooms through the native serializer without unloading
    // them or executing entry callbacks. Offline actors join only this borrowed
    // save roster; they never reappear in live combat during checkpointing.
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->replicaShell)
            continue;
        Scope scope(*room);
        originalSave(reinterpret_cast<void*>(room->pointer));
    }
    auto all = values(roster());
    for (const auto& [slot, parked] : dormant) {
        (void)slot;
        all.insert(all.end(), parked.actors.begin(), parked.actors.end());
    }
    std::stable_sort(all.begin(), all.end(),
                     [](Address a, Address b) { return at<int>(a, 0x1618) < at<int>(b, 0x1618); });
    ViewRoster saved(all);
    capture();
    return true;
}
bool takeFloorChange() {
    const bool value = floorChanged;
    floorChanged = false;
    return value;
}
bool receiveRoomRequest(unsigned slot, const lan::RoomRequest& request) {
    if (slot >= 4 || runtime::replica() || !stateReady() || !(connectedMask & (1u << slot)) ||
        at<int>(game(), 0) != request.stage || at<int>(game(), 4) != request.type)
        return false;
    const auto head = participant(slot);
    const auto from = findRoom(head);
    if (!from || from->key.index != request.source ||
        from->key.dimension != request.sourceDimension)
        return false;
    return queue(head, request.destination, request.dimension, -1, request.teleport);
}
std::vector<SavedLocation> captureLocations() {
    std::vector<SavedLocation> result;
    if (!enabled || depth)
        return result;
    for (unsigned slot = 0; slot < 4; ++slot) {
        if (auto parked = dormant.find(slot); parked != dormant.end()) {
            result.push_back(parked->second.saved);
            continue;
        }
        const auto player = participant(slot);
        if (!player)
            continue;
        const auto room = findRoom(player);
        if (!room)
            return {};
        result.push_back({room->key.dimension, room->key.index, at<float>(player, 0x33c),
                          at<float>(player, 0x340)});
    }
    return result;
}
void setConnected(unsigned mask) {
    connectedMask = mask | 1u;
    if (!enabled || depth)
        return;
    bool changed = false;
    for (unsigned slot = 1; slot < 4; ++slot) {
        const auto head = participant(slot);
        if (!(connectedMask & (1u << slot)) && head) {
            auto from = findRoom(head);
            if (!from)
                continue;
            Dormant parked;
            parked.saved = {from->key.dimension, from->key.index, at<float>(head, 0x33c),
                            at<float>(head, 0x340)};
            parked.actors = controlledActors(head);
            parked.room = std::make_unique<Room>();
            parked.room->key = {0, -99};
            parked.room->owned = true;
            parked.room->pointer = reinterpret_cast<Address>(allocate(0x7898));
            engine<RoomCall>(0x3e9400)(reinterpret_cast<void*>(parked.room->pointer));
            for (auto actor : parked.actors) {
                for (auto entity : followers(actor, *from))
                    moveEntity(entity, *from, *parked.room);
                moveEntity(actor, *from, *parked.room);
                location.erase(actor);
            }
            auto all = values(roster());
            for (auto actor : parked.actors)
                std::erase(all, actor);
            assign(roster(), all);
            dormant.emplace(slot, std::move(parked));
            participants = logicalPlayers();
            changed = true;
            logger("player_dormant slot=" + std::to_string(slot));
        } else if ((connectedMask & (1u << slot)) && dormant.contains(slot)) {
            auto& parked = dormant.at(slot);
            auto root = findRoom(participant(0));
            if (!root)
                continue;
            const auto host = participant(0);
            const Vec2 target{at<float>(host, 0x33c) + 12, at<float>(host, 0x340)};
            auto all = values(roster());
            for (auto actor : parked.actors) {
                for (auto entity : followers(actor, *parked.room)) {
                    moveEntity(entity, *parked.room, *root);
                    place(entity, target);
                }
                moveEntity(actor, *parked.room, *root);
                place(actor, target);
                location[actor] = root;
                all.push_back(actor);
            }
            std::stable_sort(all.begin(), all.end(), [](Address a, Address b) {
                return at<int>(a, 0x1618) < at<int>(b, 0x1618);
            });
            assign(roster(), all);
            participants = logicalPlayers();
            destroy(*parked.room);
            dormant.erase(slot);
            changed = true;
            logger("player_returned slot=" + std::to_string(slot));
        }
    }
    const auto all = values(roster());
    for (unsigned i = 0; i < all.size(); ++i)
        at<unsigned>(all[i], 0x161c) = i;
    if (changed) {
        using GetHUD = void*(__attribute__((thiscall))*)(void*);
        engine<RoomCall>(0x5a8620)(engine<GetHUD>(0x178e0)(reinterpret_cast<void*>(game())));
    }
    canonical();
}
void protectArrivals(unsigned mask) {
    using Cooldown = void(__attribute__((thiscall))*)(void*, int);
    for (unsigned slot = 0; slot < 4; ++slot)
        if (mask & (1u << slot)) {
            const auto head = participant(slot);
            if (!head)
                continue;
            const auto room = findRoom(head);
            if (!room || !occupiedCombat(*room, head))
                continue;
            for (auto actor : controlledActors(head))
                engine<Cooldown>(0x361d0)(reinterpret_cast<void*>(actor), 90);
        }
}
unsigned connected() {
    return connectedMask;
}
unsigned soundAudience() {
    if (!enabled)
        return 0;
    const auto current = at<Address>(game(), 0x18300);
    unsigned mask = 0;
    for (auto player : participants)
        if (const auto room = findRoom(player); room && room->pointer == current)
            mask |= 1u << slotOf(player);
    return mask;
}
std::uintptr_t presentationPlayer(void* explicitPlayer) {
    return enabled ? currentActor(explicitPlayer) : 0;
}
bool withPlayer(unsigned slot, const std::function<void()>& call) {
    const auto head = slot < 4 ? participant(slot) : 0;
    const auto room = head ? findRoom(head) : nullptr;
    if (!enabled || depth || !room || !(connectedMask & (1u << slot)))
        return false;
    Scope scope(*room, controlledActors(head));
    call();
    return true;
}
bool gatherForTransition(const std::function<void()>& begin) {
    if (!enabled || runtime::replica() || !active)
        return false;
    if (!pendingTeamTransition)
        pendingTeamTransition = TeamTransition{active->key, begin};
    return true;
}
bool restoreLocations(const std::vector<SavedLocation>& saved) {
    if (!enabled || depth || saved.size() != participants.size())
        return false;
    // Apply saved positions to the complete restored roster before parking
    // offline actors. Otherwise their dormant position captures the native
    // Continue spawn point on one machine and the saved point on another.
    const auto mask = connectedMask;
    setConnected(15);
    for (unsigned slot = 0; slot < saved.size(); ++slot) {
        if (runtime::replica() && slot != static_cast<unsigned>(runtime::localViewSlot()))
            continue;
        if (!queue(participants[slot], saved[slot].index, saved[slot].dimension, -1))
            return false;
    }
    finishFrame();
    for (unsigned slot = 0; slot < saved.size(); ++slot) {
        if (runtime::replica() && slot != static_cast<unsigned>(runtime::localViewSlot()))
            projectRemote(slot, saved[slot]);
        const auto head = participants[slot];
        const auto room = findRoom(head);
        const Vec2 target{saved[slot].x, saved[slot].y};
        for (auto actor : controlledActors(head)) {
            place(actor, target);
            for (auto entity : followers(actor, *room))
                place(entity, target);
        }
    }
    setConnected(mask);
    canonical();
    return true;
}
void finishFrame() {
    if (depth)
        return;
    if (pendingExit) {
        requestExit(*pendingExit);
        pendingExit.reset();
        return;
    }
    if (resumeStage && !enabled && at<int>(game(), 0x1ba78) == 0 && at<int>(game(), 0x1b83c) == 0) {
        if (adopt()) {
            resumeStage = false;
            floorChanged = true;
            if (!resumeLocations.empty()) {
                auto locations = std::move(resumeLocations);
                resumeLocations.clear();
                restoringSavedLocations = true;
                const bool restored = restoreLocations(locations);
                restoringSavedLocations = false;
                if (!restored)
                    runtime::abort("Hourglass player locations could not be restored");
            }
            logger("floor_transaction=COMPLETE stage=" + std::to_string(at<int>(game(), 0)));
        }
    }
    if (!enabled)
        return;
    if (pendingDogma) {
        const auto source = *pendingDogma;
        pendingDogma.reset();
        for (auto& [key, room] : loaded) {
            (void)key;
            if (room->pointer == source) {
                room->activate();
                break;
            }
        }
        if (!runtime::replica())
            runtime::beginStage(false, 1, false, 25);
        beforeStart();
        resumeStage = true;
        if (runtime::replica()) {
            using Movie = void(__stdcall*)(unsigned, bool, unsigned);
            engine<Movie>(0x558e60)(25, false, 1);
        }
        originalTransition(reinterpret_cast<void*>(game()), -10, -1, 1, nullptr, -1);
        originalNativeRoomChange(reinterpret_cast<void*>(game() + 0x1b83c));
        logger("cinematic_transaction=BEGIN dogma_beast");
        return;
    }
    std::function<void()> beginTeamTransition;
    if (pendingTeamTransition) {
        auto transition = std::move(*pendingTeamTransition);
        pendingTeamTransition.reset();
        for (auto head : participants)
            queue(head, transition.room.index, transition.room.dimension, -1, false, false);
        beginTeamTransition = std::move(transition.begin);
    }
    // Transformations may replace the player object while keeping its native
    // controller. Resolve that controller again before dereferencing a head.
    const auto currentParticipants = logicalPlayers();
    participants = currentParticipants;
    if (rewind::executePending())
        return;
    if (pendingRKey) {
        if (!runtime::replica()) {
            const auto locations = captureLocations();
            withCheckpointRoster([&] {
                for (unsigned slot = 0; slot < locations.size(); ++slot)
                    rewind::remember(slot, -1, locations);
            });
        }
        // Send the pre-restart Seeds. Both originals advance those values and
        // reset the same native floor; R Key's item pool remains untouched.
        runtime::beginStage(false, 0, true);
        beforeStart();
        resumeStage = true;
        originalRKey();
        logger("floor_transaction=R_KEY");
        return;
    }
    if (pendingStage) {
        const auto request = *pendingStage;
        pendingStage.reset();
        if (auto room = findRoom(request.player))
            room->activate();
        if (!runtime::replica()) {
            const auto locations = captureLocations();
            withCheckpointRoster([&] {
                for (unsigned slot = 0; slot < locations.size(); ++slot)
                    rewind::remember(slot, -1, locations);
            });
        }
        beforeStart();
        resumeStage = true;
        // A Big Chest either changes floors or ends the run. Only the host
        // evaluates that native decision; a terminal chest must not also send
        // a speculative floor event before the reliable ending event. Evaluate
        // with the same complete roster that native departure will use.
        using ChestEnding = int(__stdcall*)(bool);
        if (request.animation != 4 || runtime::replica() ||
            engine<ChestEnding>(0x2f9d20)(false) == 0)
            runtime::beginStage(request.same, request.animation);
        logger("floor_transaction=BEGIN same=" + std::to_string(request.same));
        // Replicas never simulate the chest collector or its grid markers.
        // Use native fade/loading rather than waiting for those local markers
        // and re-evaluating the chest against the replica's unlocks/inventory.
        const auto animation = runtime::replica() && request.animation == 4 ? 1 : request.animation;
        originalStage(reinterpret_cast<void*>(game()), request.same, animation,
                      reinterpret_cast<void*>(request.player));
        return;
    }
    setConnected(connectedMask);
    if (!runtime::replica()) {
        // Vanilla global room changes carry co-op ghosts with living players.
        // Per-player transfers need that same rule when the last survivor
        // leaves a room, including a death that occurs while already split.
        for (const auto ghost : participants) {
            if (!at<bool>(ghost, 0x20a9))
                continue;
            const auto source = findRoom(ghost);
            const auto livingHere =
                std::any_of(participants.begin(), participants.end(), [&](Address p) {
                    return !at<bool>(p, 0x20a9) && findRoom(p) == source;
                });
            if (!source || livingHere)
                continue;
            const auto survivor = std::find_if(participants.begin(), participants.end(),
                                               [](Address p) { return !at<bool>(p, 0x20a9); });
            if (survivor != participants.end())
                if (const auto target = findRoom(*survivor))
                    queue(ghost, target->key.index, target->key.dimension, -1);
        }
    }
    if (pending.empty() && pendingItemRevival.empty()) {
        preparedDepartures.clear();
        if (beginTeamTransition)
            beginTeamTransition();
        return;
    }
    auto requests = std::move(pending);
    pending.clear();
    for (const auto& request : requests) {
        Room* from = findRoom(request.player);
        if (!from || from->key == request.destination)
            continue;
        using Finished = bool(__attribute__((thiscall))*)(void*, const char*);
        // TeleportOut holds the extra-animation flag until ChangeRoom. Waiting
        // for that flag to clear deadlocks the transition; wait for the native
        // sprite's last frame, then replace it with TeleportIn on arrival.
        if (request.teleport && request.animateDeparture && at<bool>(request.player, 0x1398) &&
            !engine<Finished>(0xa550)(reinterpret_cast<void*>(request.player + 0x48), "")) {
            pending.push_back(request);
            continue;
        }
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        auto desc = reinterpret_cast<Address>(
            engine<Desc>(0x340bc0)(reinterpret_cast<void*>(game()), request.destination.index,
                                   request.destination.dimension));
        if (!desc || !at<Address>(desc, 0x10)) {
            logger("room_transfer=invalid_destination");
            continue;
        }
        if (!runtime::replica() && !restoringSavedLocations) {
            const auto locations = captureLocations();
            withCheckpointRoster([&] {
                Scope scope(*from, values(roster()));
                rewind::remember(slotOf(request.player), request.door, locations);
            });
        }
        auto found = loaded.find(request.destination);
        Room* to;
        const bool created = found == loaded.end() || found->second->replicaShell;
        if (found == loaded.end()) {
            auto room = std::make_unique<Room>();
            room->pointer = reinterpret_cast<Address>(allocate(0x7898));
            room->owned = true;
            engine<RoomCall>(0x3e9400)(reinterpret_cast<void*>(room->pointer));
            room->key = request.destination;
            room->context = from->context;
            to = room.get();
            loaded.emplace(request.destination, std::move(room));
        } else {
            to = found->second.get();
            // Remote actors use an uninitialized storage shell. When this
            // becomes the displayed room, native ChangeRoom still needs the
            // departure room's previous-index/dimension context.
            if (to->replicaShell)
                to->context = from->context;
        }
        const bool protect = !created && occupiedCombat(*to, request.player);
        if (created)
            prepareDepartureMetadata(
                std::span<std::uint32_t, 3>(reinterpret_cast<std::uint32_t*>(to->pointer), 3),
                std::span<const std::uint32_t, 3>(
                    reinterpret_cast<const std::uint32_t*>(from->pointer), 3));
        to->replicaShell = false;
        const auto actors = controlledActors(request.player);
        std::vector<Address> companions;
        for (auto player : actors)
            for (auto entity : followers(player, *from))
                if (std::find(companions.begin(), companions.end(), entity) == companions.end())
                    companions.push_back(entity);
        {
            Scope scope(*from, actors);
            // Game::ChangeRoom normally performs this before Level::ChangeRoom.
            // Door transitions queued by our adapter bypass that wrapper. Run
            // its native per-player cleanup once, including room-limited stats.
            for (auto player : actors)
                if (!preparedDepartures.contains(player))
                    originalLeave(reinterpret_cast<void*>(player), false);
        }
        for (auto player : actors) {
            for (auto entity : followers(player, *from))
                if (std::find(companions.begin(), companions.end(), entity) == companions.end())
                    companions.push_back(entity);
            moveEntity(player, *from, *to);
            location[player] = to;
        }
        for (auto entity : companions)
            // A fresh native Room::Init discards ordinary NPCs already in its
            // entity list. Insert Dark Esau after initialization, while the
            // source room still owns him; familiars retain their normal path.
            if (!created || at<unsigned>(entity, 0x28) != 866)
                moveEntity(entity, *from, *to);
        {
            Scope scope(*to, actors);
            if (created) {
                transferring = true;
                skipSave = to->pointer;
                // The request already resolves a destination. J460 otherwise
                // reuses LeaveDoor from the preceding transition and replaces
                // that destination with the old room's neighbor (0x340432).
                // Arrival below applies our explicit entry door afterward.
                at<int>(game(), 0x18318) = -1;
                at<int>(game(), 0x1831c) = request.door;
                originalChange(reinterpret_cast<void*>(game()), request.destination.index,
                               request.destination.dimension);
                if (!runtime::replica())
                    engine<RoomCall>(0x3eb1b0)(reinterpret_cast<void*>(to->pointer));
                skipSave = 0;
                transferring = false;
                for (auto entity : companions)
                    if (at<unsigned>(entity, 0x28) == 866)
                        moveEntity(entity, *from, *to);
            } else {
                // Joining an occupied room must apply the arriving characters'
                // entry effects without reinitializing resident entities.
                for (auto player : actors)
                    engine<RoomCall>(0x3a8350)(reinterpret_cast<void*>(player));
                for (auto entity : companions)
                    if (at<unsigned>(entity, 0x28) == 3)
                        engine<RoomCall>(0x22c8a0)(reinterpret_cast<void*>(entity));
            }
            arrival(request.player, *to, request.door, companions, protect);
            for (auto player : actors)
                if (player != request.player)
                    arrival(player, *to, request.door, {}, protect);
            runtime::roomEntered();
            if (created)
                presentation::roomEntered(to->pointer);
            if (!created) {
                // J460's native POST_NEW_ROOM dispatcher (callback 19). A
                // resident room needs the entry notification without Init;
                // local Mod interfaces must not keep the departure descriptor.
                engine<PostUpdate>(0x465180)();
            }
            if (request.teleport) {
                using Animate = void(__attribute__((thiscall))*)(void*, bool);
                for (auto p : actors) {
                    engine<Animate>(0x3abcc0)(reinterpret_cast<void*>(p), false);
                    // Womb/portal effects disable ControlsEnabled themselves.
                    // Native RoomTransition releases it at completion, which
                    // our per-player transfer replaces. Keep its extra sprite
                    // animation, but release only the arriving portal actors.
                    if (!request.animateDeparture)
                        at<bool>(p, 0x410) = true;
                }
            }
        }
        canonical();
        logger("room_transfer slot=" + std::to_string(slotOf(request.player)) +
               " from=" + std::to_string(from->key.index) + " to=" + std::to_string(to->key.index) +
               " created=" + std::to_string(created));
    }
    preparedDepartures.clear();
    if (beginTeamTransition)
        beginTeamTransition();
    for (auto slot : pendingItemRevival)
        if (const auto head = participant(slot)) {
            for (auto player : controlledActors(head)) {
                // Same visibility exclusion as native RoomTransition::ChangeRoom.
                if (!(at<unsigned>(player, 0x16c) & 0x02000000u))
                    at<bool>(player, 0x171) = true;
                using Cooldown = void(__attribute__((thiscall))*)(void*, int);
                engine<Cooldown>(0x361d0)(reinterpret_cast<void*>(player), 90);
            }
        }
    pendingItemRevival.clear();
    // Empty rooms return to the game's RoomDescriptor save format. Re-entering
    // creates a fresh room through native initialization, preserving cleared
    // enemies/pickups while resetting transient room state as vanilla does.
    for (auto it = loaded.begin(); it != loaded.end();) {
        if (!occupants(*it->second).empty()) {
            ++it;
            continue;
        }
        {
            Scope scope(*it->second);
            if (!it->second->replicaShell && !runtime::replica())
                originalSave(reinterpret_cast<void*>(it->second->pointer));
        }
        logger("room_unload index=" + std::to_string(it->first.index));
        destroy(*it->second);
        it = loaded.erase(it);
    }
}
void resumeAfterTransition(std::vector<SavedLocation> locations) {
    resumeLocations = std::move(locations);
    resumeStage = true;
}
void requestExit(bool save) {
    // Game::Exit only frees the run; Manager owns the switch back to menus.
    // Queue the native menu transaction so no caller keeps a freed camera and
    // the next Manager update cannot mistakenly re-enter gameplay.
    const auto manager = at<Address>(image, 0x87169c);
    at<bool>(manager, 0x4b284) = save;
    at<int>(manager, 0x4b28c) = 2;
    using Transition = void(__attribute__((thiscall))*)(void*, int);
    engine<Transition>(0x60f550)(reinterpret_cast<void*>(manager + 0x4b290), -1);
    at<bool>(manager, 0x4b288) = true;
}
void playEnding(unsigned ending) {
    // Native local co-op can wait for every roster member to enter the chest.
    // The host has already accepted this terminal event for the whole run.
    auto head = participant(runtime::localViewSlot());
    if (!head) {
        const auto players = logicalPlayers();
        const auto slot = static_cast<unsigned>(runtime::localViewSlot());
        if (slot < players.size())
            head = players[slot];
    }
    if (!head) {
        runtime::abort("Native ending player is missing");
        return;
    }
    const ViewRoster view(controlledActors(head));
    originalEnd(reinterpret_cast<void*>(game()), static_cast<int>(ending));
}
void beforeStart() {
    presentation::items::reset();
    replicaMapEntities.clear();
    for (const auto& [entry, original] : entityUpdates) {
        (void)original;
        MH_DisableHook(reinterpret_cast<void*>(entry));
        MH_RemoveHook(reinterpret_cast<void*>(entry));
    }
    entityUpdates.clear();
    // Game restart owns destruction of the canonical room and global players.
    // Additional room destruction must happen before that native cleanup.
    resumeStage = false;
    pendingStage.reset();
    pendingTeamTransition.reset();
    pendingRKey = false;
    pendingDogma.reset();
    resumeLocations.clear();
    if (!enabled || depth)
        return;
    // Native floor changes and saves own the complete player roster. Reattach
    // dormant actors for that transaction, then park them again on the new
    // floor if their controllers are still offline.
    // A guest may enter a chest while the host is in another room. Restoring
    // dormant actors canonicalizes the viewport; native departure must still
    // use the initiating room, including its chest and arrival animation.
    const auto source = at<Address>(game(), 0x18300);
    const auto mask = connectedMask;
    setConnected(15);
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->pointer == source) {
            room->activate();
            break;
        }
    }
    connectedMask = mask;
    enabled = false;
    pending.clear();
    preparedDepartures.clear();
    pendingItemRevival.clear();
    Room* root = nullptr;
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->pointer == at<Address>(game(), 0x18300))
            root = room.get();
    }
    if (root) {
        for (const auto& [player, room] : location)
            if (room != root) {
                for (auto entity : followers(player, *room))
                    moveEntity(entity, *room, *root);
                moveEntity(player, *room, *root);
            }
        root->owned = false;
        root->activate();
    }
    sharedOwner = nullptr; // Native cleanup retains root's queue and light texture.
    for (auto& [key, room] : loaded) {
        (void)key;
        destroy(*room);
    }
    loaded.clear();
    location.clear();
    participants.clear();
}
void withMapPickups(const std::function<void()>& cache) {
    if (!runtime::replica()) {
        cache();
        return;
    }
    struct Restore {
        std::vector<std::pair<Address, Vector>> vectors;
        ~Restore() {
            for (const auto& [descriptor, vector] : vectors)
                at<Vector>(descriptor, 0x74) = vector;
        }
    } restore;
    using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
    for (const auto& [key, entities] : replicaMapEntities) {
        const auto descriptor = reinterpret_cast<Address>(
            engine<Desc>(0x340bc0)(reinterpret_cast<void*>(game()), key.index, key.dimension));
        if (!descriptor || !at<Address>(descriptor, 0x10))
            continue;
        restore.vectors.emplace_back(descriptor, at<Vector>(descriptor, 0x74));
        const auto begin = reinterpret_cast<Address>(entities.data());
        const auto end = begin + entities.size() * sizeof(MapEntity);
        at<Vector>(descriptor, 0x74) = {begin, end, end};
    }
    cache();
}
bool install(Address base, void (*log)(const std::string&)) {
    image = base;
    logger = log;
    auto hook = [](Address rva, void* replacement, void** original) {
        return MH_CreateHook(reinterpret_cast<void*>(image + rva), replacement, original) ==
                   MH_OK &&
               MH_EnableHook(reinterpret_cast<void*>(image + rva)) == MH_OK;
    };
    return hook(0x359400, reinterpret_cast<void*>(addCoins),
                reinterpret_cast<void**>(&originalCoins)) &&
           hook(0x5bee80, reinterpret_cast<void*>(replacePlayer),
                reinterpret_cast<void**>(&originalReplacePlayer)) &&
           hook(0x3597e0, reinterpret_cast<void*>(syncResources),
                reinterpret_cast<void**>(&originalResources)) &&
           hook(0x2f9770, reinterpret_cast<void*>(endGame),
                reinterpret_cast<void**>(&originalEnd)) &&
           hook(0x3efa50, reinterpret_cast<void*>(save), reinterpret_cast<void**>(&originalSave)) &&
           hook(0x33fc80, reinterpret_cast<void*>(change),
                reinterpret_cast<void**>(&originalChange)) &&
           hook(0x4318a0, reinterpret_cast<void*>(nativeRoomChange),
                reinterpret_cast<void**>(&originalNativeRoomChange)) &&
           hook(0x2fd7c0, reinterpret_cast<void*>(transition),
                reinterpret_cast<void**>(&originalTransition)) &&
           hook(0x2fdc10, reinterpret_cast<void*>(stageTransition),
                reinterpret_cast<void**>(&originalStage)) &&
           hook(0x307ad0, reinterpret_cast<void*>(rKey), reinterpret_cast<void**>(&originalRKey)) &&
           hook(0x5bf990, reinterpret_cast<void*>(isCoop),
                reinterpret_cast<void**>(&originalIsCoop)) &&
           hook(0x5bfa00, reinterpret_cast<void*>(living),
                reinterpret_cast<void**>(&originalLiving)) &&
           hook(0x5bfa70, reinterpret_cast<void*>(dead), reinterpret_cast<void**>(&originalDead)) &&
           hook(0x5bfae0, reinterpret_cast<void*>(reviveAll),
                reinterpret_cast<void**>(&originalReviveAll)) &&
           hook(0x3fb250, reinterpret_cast<void*>(award),
                reinterpret_cast<void**>(&originalAward)) &&
           hook(0x2fa0c0, reinterpret_cast<void*>(exitGame),
                reinterpret_cast<void**>(&originalExit)) &&
           hook(0x3a6680, reinterpret_cast<void*>(leaveRoom),
                reinterpret_cast<void**>(&originalLeave)) &&
           hook(0x5439d0, reinterpret_cast<void*>(cameraSmooth),
                reinterpret_cast<void**>(&originalCameraSmooth)) &&
           hook(0x5446e0, reinterpret_cast<void*>(cameraDrag),
                reinterpret_cast<void**>(&originalCameraDrag)) &&
           hook(0x5beba0, reinterpret_cast<void*>(playersCenter),
                reinterpret_cast<void**>(&originalPlayersCenter)) &&
           hook(0x30c5c0, reinterpret_cast<void*>(doorUpdate),
                reinterpret_cast<void**>(&originalDoorUpdate)) &&
           hook(0x31fef0, reinterpret_cast<void*>(trapdoorUpdate),
                reinterpret_cast<void**>(&originalTrapdoorUpdate)) &&
           hook(0x14f670, reinterpret_cast<void*>(needleVisual),
                reinterpret_cast<void**>(&originalNeedleVisual)) &&
           hook(0x4607a0, reinterpret_cast<void*>(postUpdate),
                reinterpret_cast<void**>(&originalPostUpdate)) &&
           hook(0x465180, reinterpret_cast<void*>(postNewRoom),
                reinterpret_cast<void**>(&originalPostNewRoom));
}
bool bind(lua_State* L, HMODULE module) {
#define IMPORT(field, name)                                                                        \
    do {                                                                                           \
        auto p = GetProcAddress(module, name);                                                     \
        memcpy(&lua.field, &p, sizeof(p));                                                         \
        if (!lua.field)                                                                            \
            return false;                                                                          \
    } while (false)
    IMPORT(pushClosure, "lua_pushcclosure");
    IMPORT(setField, "lua_setfield");
    IMPORT(pushBoolean, "lua_pushboolean");
    IMPORT(pushInteger, "lua_pushinteger");
    IMPORT(createTable, "lua_createtable");
    IMPORT(checkInteger, "luaL_checkinteger");
    IMPORT(checkString, "luaL_checklstring");
    IMPORT(pushString, "lua_pushlstring");
    IMPORT(getTop, "lua_gettop");
    IMPORT(toUserdata, "lua_touserdata");
    IMPORT(newUserdata, "lua_newuserdata");
    IMPORT(rawLength, "lua_rawlen");
    IMPORT(getMetatable, "lua_getmetatable");
    IMPORT(setMetatable, "lua_setmetatable");
    IMPORT(rawSetI, "lua_rawseti");
    IMPORT(pushValue, "lua_pushvalue");
    IMPORT(pcall, "lua_pcallk");
    IMPORT(error, "lua_error");
#undef IMPORT
    auto function = [&](const char* name, LuaFn fn) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    };
    function("api_move", integrationMove);
    function("api_cancel_move", cancelIntegrationMove);
    function("api_with_local_view", withLocalView);
    function("api_actors", actorIdentities);
    function("api_with_owner", withOwner);
    function("rooms_enable", enable);
    function("rooms_move", request);
    function("rooms_with_player", withPlayer);
    function("rooms_positions", positions);
    function("r_key_begin", beginRKey);
    function("rooms_ready", ready);
    function("rooms_heads", heads);
    function("rooms_sync", syncLocations);
    function("state_clock", stateClock);
    function("room_layout", roomLayout);
    function("map_pickups", mapPickups);
    function("map_refresh", refreshMap);
    function("actor_sprites", actorSprites);
    function("actor_form", actorForm);
    function("actor_poop", actorPoop);
    function("actor_ghost", actorGhost);
    function("laser_path", laserPath);
    function("rooms_set_connected", setConnections);
    function("rooms_connected", connections);
    function("rooms_begin_floor", beginFloor);
    function("rooms_begin_cinematic", beginCinematic);
    return visuals::bind(L, module);
}
} // namespace isaac::rooms

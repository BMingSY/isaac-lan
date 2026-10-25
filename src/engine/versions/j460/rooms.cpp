#include "engine/item_effects.h"
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "engine/pause_menu.h"
#include "engine/visuals.h"
#include "engine/audio.h"
#include "engine/combat_feedback.h"
#include "engine/input.h"
#include "engine/rewind.h"
#include "engine/presentation.h"
#include "engine/item_presentation.h"
#include "engine/pickup_preview.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include "core/laser_state.h"
#include "runtime/room_map.h"
#include "compat/bosses/encounters.h"
#include "compat/bosses/rotgut.h"
#include "compat/routes/mines.h"
#include "compat/routes/mirror.h"
#include "compat/routes/curses.h"
#include "compat/routes/home.h"
#include "compat/items/deal_chances.h"
#include "compat/items/death_certificate.h"
#include "compat/items/room_transitions.h"
#include "runtime/room_clock.h"
#include "compat/items/crafting_bag.h"
#include "compat/items/team_effects.h"
#include "compat/characters/traits.h"
#include "compat/characters/ghost.h"
#include "compat/characters/keeper.h"
#include "compat/characters/team_effects.h"
#include "runtime/actor_roster.h"
#include "runtime/room_scope.h"
#include "core/poop_state.h"
#include "presentation/ambient_effects.h"
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
#include <limits>

#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/floor_source.h"
#include "engine/versions/j460/room_routing.h"
namespace j460 = isaac::engine::j460;

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
    return at<Address>(image, j460::globals::game);
}
using Allocate = void*(__cdecl*)(std::size_t);
using Delete = void(__cdecl*)(void*, std::size_t);
void* allocate(std::size_t size) {
    return engine<Allocate>(j460::entry::engineRoomsAllocate)(size);
}
void release(Address p, std::size_t size) {
    if (p)
        engine<Delete>(j460::entry::engineRoomsDelete)(reinterpret_cast<void*>(p), size);
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
constexpr std::array<std::size_t, 35> contextOffsets = {
    0x18304, 0x18308, 0x1830c, 0x18310, 0x18318, 0x1831c, 0x182c8, 0x1ad90,
    // Native special-room exits and arrival positioning consume this origin.
    // It belongs to the selected room, not the host's canonical viewport.
    0x18320, 0x18324, 0x18328,
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
    RoomClock clock;
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
// Non-owning identities of replica-only parented bodies. Native PlayerManager
// owns their allocations; the map is invalidated before native run teardown.
std::map<unsigned, Address> replicaCompanions;
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
ScopeStack<Room, Vector> scopes;
bool enabled = false, transferring = false;
Address skipSave = 0;
enum class RoomRouting { native, resolved };
struct Request {
    Address player;
    Key destination;
    int door;
    bool teleport;
    bool animateDeparture;
    int animation;
    std::optional<Vec2> landing;
    RoomRouting routing;
};
std::vector<Request> pending;
std::set<unsigned> pendingItemRevival;
struct StageRequest {
    bool same;
    int animation;
    Address player;
    int sourceRoom;
};
std::optional<StageRequest> pendingStage;
j460::FloorSource floorSource;
struct TeamTransition {
    Key room;
    std::function<void()> begin;
};
std::optional<TeamTransition> pendingTeamTransition;
unsigned pendingRestart = 0;
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
using VictoryLap = void(__attribute__((thiscall)) *)(void*);
VictoryLap originalVictoryLap;
std::optional<bool> pendingExit;
bool resumeStage = false;
std::vector<SavedLocation> resumeLocations;
bool restoringSavedLocations = false;
using StageTransition = void(__attribute__((thiscall)) *)(void*, bool, int, void*);
StageTransition originalStage;
RoomCall originalNextStage;
void __attribute__((fastcall)) nextStage(void* level, void*) {
    floorSource.select(at<int>(reinterpret_cast<Address>(level), 0x18304),
                       [&] { originalNextStage(level); });
}
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
    Room* room;
    Room* previousShared;
    Address previousRoom;
    std::array<std::uint32_t, contextOffsets.size()> previous;
    bool previousRefresh;
    unsigned char previousSnapshot;
    Vector previousRoster;
    Vector nestedScratch;
    Vector* storage;
    std::optional<ScopeStack<Room, Vector>::Binding> binding;
    std::optional<audio::RoomScope> audioScope;
    bool reconcilePlayers;
    std::vector<Address> originalPlayers;
    std::map<Address, int> originalControllers;
    Scope(Room& target, const std::vector<Address>& players, bool reconcile = true)
        : room(&target), previousShared(sharedOwner), previousRoom(at<Address>(game(), 0x18300)),
          previousRoster(roster()), reconcilePlayers(reconcile), originalPlayers(players) {
        for (auto player : players)
            originalControllers[player] = at<int>(player, 0x1618);
        for (unsigned i = 0; i < previous.size(); ++i)
            previous[i] = at<std::uint32_t>(game(), contextOffsets[i]);
        previousRefresh = at<bool>(game(), 0x26534);
        previousSnapshot = at<unsigned char>(game(), 0x26540);
        // A display callback can scope the same room again. Its temporary
        // roster must not overwrite an outer scope's live allocation.
        storage = scopes.depth() ? &nestedScratch : &room->scratch;
        assign(*storage, players);
        roster() = *storage;
        room->activate();
        binding.emplace(scopes, *room, previousRoster);
        audioScope.emplace();
    }
    explicit Scope(Room& target) : Scope(target, occupants(target)) {}
    Scope(const Scope&) = delete;
    Scope& operator=(const Scope&) = delete;
    void enter(Room& target) {
        audioScope.reset();
        room = &target;
        room->activate();
        binding->enter(target);
        audioScope.emplace();
    }
    ~Scope() {
        audioScope.reset();
        room->capture();
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
                    location[player] = room;
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
            if (scopes.depth() == 1)
                participants = logicalPlayers();
        }
        at<Address>(game(), 0x18300) = previousRoom;
        for (unsigned i = 0; i < previous.size(); ++i)
            at<std::uint32_t>(game(), contextOffsets[i]) = previous[i];
        at<bool>(game(), 0x26534) = previousRefresh;
        at<unsigned char>(game(), 0x26540) = previousSnapshot;
        binding->restoreParent();
        selectSharedState(previousShared);
        if (storage == &nestedScratch)
            release(nestedScratch.begin, nestedScratch.capacity - nestedScratch.begin);
        binding.reset();
    }
};
struct TeamScope {
    Vector saved;
    bool changed;
    TeamScope() : saved(roster()), changed(enabled && scopes.teamRoster()) {
        if (changed)
            roster() = *scopes.teamRoster();
    }
    TeamScope(const TeamScope&) = delete;
    TeamScope& operator=(const TeamScope&) = delete;
    ~TeamScope() {
        if (changed) {
            *scopes.teamRoster() = roster();
            roster() = saved;
        }
    }
};
using FindCollectible = void*(__attribute__((thiscall)) *)(void*, int, void*, bool);
using CollectibleCount = int(__attribute__((thiscall)) *)(void*, int);
using FindPlayerType = void*(__attribute__((thiscall)) *)(void*, int);
FindCollectible originalFindCollectible;
CollectibleCount originalCollectibleCount;
FindPlayerType originalFindPlayerType;
void* __attribute__((fastcall)) findCollectible(void* manager, void*, int item, void* excluded,
                                                bool backup) {
    if (!compat::items::sharedCollectibleEffect(item))
        return originalFindCollectible(manager, item, excluded, backup);
    TeamScope team;
    return originalFindCollectible(manager, item, excluded, backup);
}
int __attribute__((fastcall)) collectibleCount(void* manager, void*, int item) {
    if (!compat::items::sharedCollectibleEffect(item))
        return originalCollectibleCount(manager, item);
    TeamScope team;
    return originalCollectibleCount(manager, item);
}
void* __attribute__((fastcall)) findPlayerType(void* manager, void*, int kind) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    // Share only the native shop and random collectible checks. Personal
    // character checks, including Devil buyers, keep their room/actor scope.
    using compat::characters::TeamEffect;
    const bool keeper = compat::characters::sharedCharacterEffect(kind, TeamEffect::shop) &&
                        (caller == 0x34a684 || caller == 0x41554c);
    const bool lost =
        compat::characters::sharedCharacterEffect(kind, TeamEffect::randomCollectibles) &&
        caller == j460::entry::itemPoolTaintedLostQuery + 13;
    if (!keeper && !lost)
        return originalFindPlayerType(manager, kind);
    TeamScope team;
    return originalFindPlayerType(manager, kind);
}
using GetCardEx = int(__stdcall*)(unsigned, unsigned, unsigned, unsigned, bool);
GetCardEx originalGetCardEx;
int __stdcall getCardEx(unsigned seed, unsigned special, unsigned rune, unsigned suit,
                        bool nonCards) {
    // J460 inlines its Tainted Lost lookup here rather than FindPlayerType.
    // Temporarily expose the team only when that shared trait is present.
    bool shared = false;
    {
        TeamScope team;
        shared = compat::characters::sharedCharacterEffect(
                     compat::ids::player::lostB, compat::characters::TeamEffect::randomCards) &&
                 originalFindPlayerType(reinterpret_cast<void*>(game() + 0x1baa8),
                                        compat::ids::player::lostB) != nullptr;
    }
    if (!shared)
        return originalGetCardEx(seed, special, rune, suit, nonCards);
    TeamScope team;
    return originalGetCardEx(seed, special, rune, suit, nonCards);
}
using RandomRoom = void*(__attribute__((thiscall)) *)(void*, unsigned, bool, int, int, int, int,
                                                      int, int, int, void*, int, int);
RandomRoom originalRandomRoom;
void* __attribute__((fastcall)) randomRoom(void* config, void*, unsigned seed, bool reduce,
                                           int stage, int type, int shape, int minimum, int maximum,
                                           int difficultyLow, int difficultyHigh, void* doors,
                                           int subtype, int mode) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    if (type == 2 && caller == 0x33a20a) {
        bool keeper = runtime::startingPartyHasCharacter(compat::ids::player::keeperB);
        if (enabled) {
            TeamScope team;
            keeper = originalFindPlayerType(reinterpret_cast<void*>(game() + 0x1baa8),
                                            compat::ids::player::keeperB) != nullptr;
        }
        subtype = compat::characters::sharedKeeperShopSubtype(subtype, keeper);
    }
    return originalRandomRoom(config, seed, reduce, stage, type, shape, minimum, maximum,
                              difficultyLow, difficultyHigh, doors, subtype, mode);
}
struct DealChances {
    float total, angel;
};
std::optional<DealChances> replicaDeals;
using DealTotal = float(__attribute__((thiscall)) *)(void*);
DealTotal originalDealTotal;
// The internal J460 conditional Angel query returns in XMM0, unlike public
// Lua float getters (x87). Keep that ABI confined to this version backend.
void* originalAngelShare;
__attribute__((target("sse2"))) float queryAngelShare(void* query) {
    float result;
    __asm__ __volatile__("call *%1\n\tmovss %%xmm0, %0"
                         : "=m"(result)
                         : "r"(query)
                         : "eax", "ecx", "edx", "xmm0", "xmm1", "xmm2", "xmm3", "xmm4", "xmm5",
                           "xmm6", "xmm7", "memory", "cc");
    return result;
}
// The native total query applies an extra penalty only while its current
// descriptor is the final boss room. Borrow that room for this read so moving
// to a different room cannot hide a teammate's boss-room red-heart damage.
struct DealRoomScope {
    Address previousRoom = at<Address>(game(), 0x18300);
    int previousIndex = at<int>(game(), 0x18304);
    int previousDimension = at<int>(game(), 0x1830c);
    DealRoomScope() {
        if (!enabled)
            return;
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        for (const auto& [key, room] : loaded) {
            if (room->replicaShell)
                continue;
            const auto descriptor =
                reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
                    reinterpret_cast<void*>(game()), key.index, key.dimension));
            if (descriptor && at<int>(descriptor, 8) == at<int>(game(), 0x18314)) {
                at<Address>(game(), 0x18300) = room->pointer;
                at<int>(game(), 0x18304) = key.index;
                at<int>(game(), 0x1830c) = key.dimension;
                break;
            }
        }
    }
    ~DealRoomScope() {
        at<Address>(game(), 0x18300) = previousRoom;
        at<int>(game(), 0x18304) = previousIndex;
        at<int>(game(), 0x1830c) = previousDimension;
    }
};
float __attribute__((fastcall)) dealTotal(void* room, void*) {
    if (enabled && runtime::replica() && replicaDeals)
        return replicaDeals->total;
    TeamScope team;
    if (!enabled)
        return originalDealTotal(room);
    DealRoomScope context;
    auto total = originalDealTotal(reinterpret_cast<void*>(at<Address>(game(), 0x18300)));
    // Temporary native deal guarantees are held by a Room, rather than an
    // inventory. Include those in other loaded rooms once, without copying
    // effects/items, stacking duplicates, or changing their native lifetime.
    for (const auto& [key, candidate] : loaded)
        if (!candidate->replicaShell)
            total = compat::items::sharedRoomDealChance(
                total, originalDealTotal(reinterpret_cast<void*>(candidate->pointer)));
    return total;
}
extern "C" __attribute__((used)) float __cdecl isaac_lan_angel_share() {
    if (enabled && runtime::replica() && replicaDeals)
        return replicaDeals->angel;
    TeamScope team;
    return queryAngelShare(originalAngelShare);
}
extern "C" __attribute__((naked)) void isaac_lan_angel_share_thunk() {
    __asm__ __volatile__("subl $12, %esp\n\tcall _isaac_lan_angel_share\n\tfstps (%esp)\n\t"
                         "movss (%esp), %xmm0\n\taddl $12, %esp\n\tret");
}
using InitializeDeals = void(__attribute__((thiscall)) *)(void*, bool, bool);
InitializeDeals originalInitializeDeals;
void __attribute__((fastcall)) initializeDeals(void* level, void*, bool angel, bool devil) {
    TeamScope team;
    originalInitializeDeals(level, angel, devil);
}
using SpawnDeals = bool(__attribute__((thiscall)) *)(void*, bool, bool);
SpawnDeals originalSpawnDeals;
bool __attribute__((fastcall)) spawnDeals(void* room, void*, bool animate, bool force) {
    if (enabled && runtime::replica())
        return false;
    TeamScope team;
    return originalSpawnDeals(room, animate, force);
}
using ReplacePlayer = bool(__attribute__((thiscall)) *)(void*, void*, void*);
RoomCall originalPlayerRoomClear;
void __attribute__((fastcall)) playerRoomClear(void* player, void*) {
    // Replica Room::Update still reclaims allocations and updates doors. Its
    // clear callback must not trigger actor gameplay (including native Flip)
    // after the authoritative actor state has already been restored.
    if (enabled && runtime::replica())
        return;
    const auto owner =
        at<int>(reinterpret_cast<Address>(player), j460::layout::player::controller) - 1;
    const auto dimension = at<int>(game(), j460::layout::game::dimension);
    const auto index = at<int>(game(), j460::layout::game::roomIndex);
    originalPlayerRoomClear(player);
    if (enabled)
        runtime::playerRoomCleared(owner, dimension, index);
}
ReplacePlayer originalReplacePlayer;
bool __attribute__((fastcall)) replacePlayer(void* manager, void*, void* oldPlayer,
                                             void* nextPlayer) {
    const auto old = reinterpret_cast<Address>(oldPlayer),
               next = reinterpret_cast<Address>(nextPlayer);
    // Birthright's listed Lazarus bodies are swapped by their GLOBAL indices.
    // A room-local roster can contain both bodies at different indices.
    if (!enabled || !scopes.teamRoster() || !at<bool>(next, 0x170))
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
            engine<CopyResources>(j460::entry::entityPlayerCopyResourcesTo)(
                player, reinterpret_cast<void*>(actor), shared);
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
    if (!enabled || scopes.depth() || transferring) {
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
    if (!enabled || scopes.depth() || transferring) {
        originalCameraDrag(camera);
        return;
    }
    if (runtime::replica())
        return;
    const auto manager = *reinterpret_cast<Address*>(image + j460::globals::manager);
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
    // LAN challenges complete through their explicit reward transaction.
    // Native terminal routes cannot publish a second completion path.
    if (runtime::challengeActive() && ending >= static_cast<int>(lan::ending::firstCinematic) &&
        ending <= static_cast<int>(lan::ending::lastCinematic))
        return;
    if (runtime::localViewSlot() < 0 || ending < static_cast<int>(lan::ending::gameOver) ||
        ending > static_cast<int>(lan::ending::lastCinematic)) {
        originalEnd(target, ending);
        return;
    }
    // Native pickups/NPCs can call End while this actor's room is scoped. Keep
    // that native roster and ending semantics, then include earned progress.
    // Game::End(1) is the native game-over screen. Replicas do not simulate
    // lethal damage, so they must receive this terminal event too.
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
    if (enabled && scopes.current()) {
        const auto head = participant(runtime::localViewSlot());
        const auto it = location.find(head);
        const auto scoped = values(roster());
        if (it == location.end() || it->second != scopes.current() ||
            std::find(scoped.begin(), scoped.end(), head) == scoped.end())
            return;
    }
    originalPostNewRoom();
}
void __cdecl postUpdate() {
    if (!enabled || scopes.depth() || transferring) {
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
    if (enabled && scopes.depth()) {
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
    engine<Invalidate>(j460::entry::engineRoomsInvalidate)(
        reinterpret_cast<void*>(from.pointer + 0x1218), at<unsigned>(entity, 0x28),
        at<unsigned>(entity, 0x2c), at<unsigned>(entity, 0x30));
    at<bool>(entity, 0x170) = false;
    at<unsigned>(entity, 0x20) = at<unsigned>(to.pointer, 0x1214)++;
    using Add = void(__attribute__((thiscall))*)(void*, void*);
    engine<Add>(j460::entry::engineRoomsAdd)(reinterpret_cast<void*>(to.pointer + 0x1218),
                                             reinterpret_cast<void*>(entity));
}
std::vector<Address> followers(Address player, const Room& room, bool departingFloor = false) {
    std::vector<Address> candidates, result;
    // J460 keeps attached knives in the persistence list along with familiars;
    // transient weapons can also occur in the ordinary/effect lists. Dark Esau
    // is an NPC in the enemy list, despite following a player across rooms.
    // Preserve native iteration order and avoid transferring an entity twice.
    for (unsigned offset : {0x30u, 0x20u, 0x40u, 0x60u}) {
        const auto list = room.pointer + 0x1218 + offset;
        for (unsigned i = 0; i < at<unsigned>(list, 12); ++i) {
            const auto entity = at<Address>(at<Address>(list, 4), i * 4);
            if (std::find(candidates.begin(), candidates.end(), entity) == candidates.end())
                candidates.push_back(entity);
        }
    }
    auto owned = [player](Address entity) {
        for (unsigned ancestor = 0; entity && ancestor < 8; ++ancestor) {
            if (entity == player)
                return true;
            if (at<unsigned>(entity, 0x28) == 3)
                return at<Address>(entity, 0x410) == player;
            entity = at<Address>(entity, 0x3bc);
        }
        return false;
    };
    const bool lastOccupant =
        std::none_of(participants.begin(), participants.end(), [&](Address other) {
            const auto found = location.find(other);
            return slotOf(other) != slotOf(player) && (connectedMask & (1u << slotOf(other))) &&
                   found != location.end() && found->second == &room;
        });
    std::vector<Address> jacobs;
    for (auto occupant : occupants(room))
        if (compat::characters::taintedJacob(at<int>(occupant, 0x13c0)))
            jacobs.push_back(occupant);
    for (auto entity : candidates) {
        const auto type = at<unsigned>(entity, 0x28);
        bool darkEsau =
            type == compat::characters::darkEsau &&
            (at<Address>(player, 0x1fc0) == entity || owned(at<Address>(entity, 0x3bc)) ||
             owned(at<Address>(entity, 0x3c8)) || owned(at<Address>(entity, 0x3c4)));
        // Native room saves restore Dark Esau as an NPC without a spawner and
        // cannot restore a player's EntityPtr across our independent rooms.
        // Rebind only when the room has one unambiguous Tainted Jacob owner.
        if (type == compat::characters::darkEsau && !darkEsau && jacobs.size() == 1 &&
            jacobs[0] == player && !at<Address>(entity, 0x3bc) && !at<Address>(entity, 0x3c8) &&
            !at<Address>(entity, 0x3c4)) {
            using SetRef = void(__attribute__((fastcall))*)(void*, void*);
            engine<SetRef>(j460::entry::entityPtrAssign)(reinterpret_cast<void*>(player + 0x1fc0),
                                                         reinterpret_cast<void*>(entity));
            engine<SetRef>(j460::entry::entityPtrAssign)(reinterpret_cast<void*>(entity + 0x3c8),
                                                         reinterpret_cast<void*>(player));
            darkEsau = true;
        }
        if ((type == 3 && at<Address>(entity, 0x410) == player) ||
            (type == 8 &&
             (owned(at<Address>(entity, 0x3bc)) || owned(at<Address>(entity, 0x3c8)))) ||
            compat::items::roomFollower(type, at<unsigned>(entity, 0x2c),
                                        owned(at<Address>(entity, 0x3bc))) ||
            darkEsau ||
            (departingFloor &&
             compat::items::floorFollower(
                 type, at<unsigned>(entity, 0x2c),
                 at<Address>(player, j460::layout::player::redemptionEffect) == entity)) ||
            compat::routes::escapeFollower(type, room.key.dimension,
                                           (at<unsigned>(game(), 0x1839c) & (1u << 22)) != 0,
                                           lastOccupant))
            result.push_back(entity);
    }
    return result;
}
void place(Address entity, Vec2 position) {
    at<Vec2>(entity, 0x33c) = at<Vec2>(entity, 0x344) = position;
    at<Vec2>(entity, 0x360) = {0, 0};
    at<bool>(entity, 0x175) = false;
}
void clearRoomTransitionTarget(Address player) {
    // Native full room entry clears the attraction used by holes/chests.
    // Joining a resident room bypasses that entry, so its departing target
    // must not keep pulling the arriving actor back during normal movement.
    at<Vec2>(player, j460::layout::player::roomTransitionTarget) = {0, 0};
}
bool occupiedCombat(const Room& room, Address arriving) {
    if (room.replicaShell)
        return false;
    using IsClear = bool(__attribute__((thiscall))*)(void*);
    // J460 Room::IsClear reads its descriptor's CLEAR flag. Reuse the same
    // native predicate used by Lua, not an enemy-count approximation.
    if (engine<IsClear>(j460::entry::roomIsClear)(reinterpret_cast<void*>(room.pointer)))
        return false;
    return std::any_of(participants.begin(), participants.end(), [&](Address player) {
        const auto found = location.find(player);
        return slotOf(player) != slotOf(arriving) && (connectedMask & (1u << slotOf(player))) &&
               found != location.end() && found->second == &room;
    });
}
void arrival(Address player, const Room& room, int door, const std::vector<Address>& companions,
             bool protect, std::optional<Vec2> landing = std::nullopt) {
    if (door >= 0 && door < 8) {
        using DoorPosition = Vec2*(__attribute__((thiscall))*)(void*, Vec2*, int);
        Vec2 position;
        engine<DoorPosition>(j460::entry::engineRoomsDoorPosition)(
            reinterpret_cast<void*>(room.pointer), &position, door);
        constexpr Vec2 inward[] = {{40, 0}, {0, 40}, {-40, 0}, {0, -40}};
        position.x += inward[door % 4].x;
        position.y += inward[door % 4].y;
        landing = position;
    }
    if (landing) {
        place(player, *landing);
        for (auto entity : companions)
            if (at<unsigned>(entity, 0x28) != 867)
                place(entity, *landing);
    }
    if (protect) {
        using Cooldown = void(__attribute__((thiscall))*)(void*, int);
        engine<Cooldown>(j460::entry::engineRoomsCooldown)(reinterpret_cast<void*>(player), 90);
    }
}
void __attribute__((fastcall)) save(void* room, void*) {
    if (reinterpret_cast<Address>(room) != skipSave)
        originalSave(room);
}
using SwapRooms = bool(__attribute__((thiscall)) *)(void*, int, int);
SwapRooms originalSwapRooms;
bool __attribute__((fastcall)) swapRooms(void* level, void*, int first, int second) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    if (enabled && !runtime::replica() && caller == j460::entry::levelMazeSwapReturn) {
        const int dimension = at<int>(game(), j460::layout::game::dimension);
        auto active = [&](int index) {
            const auto room = loaded.find({dimension, index});
            if (room != loaded.end() && !room->second->replicaShell)
                return true;
            return std::any_of(dormant.begin(), dormant.end(), [&](const auto& value) {
                return value.second.room && value.second.room->key == Key{dimension, index};
            });
        };
        if (!compat::routes::allowCurseRoomSwap(active(first), active(second))) {
            logger("room_curse_swap=ACTIVE_ROOM first=" + std::to_string(first) +
                   " second=" + std::to_string(second));
            return false;
        }
    }
    return originalSwapRooms(level, first, second);
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
        // Original emote animation, dice result and expiry are local presentation too.
        engine<UpdateSprite>(j460::entry::emoteUpdate)(static_cast<char*>(player) +
                                                       j460::layout::player::emote);
        return;
    }
    const auto before = actor;
    actor = reinterpret_cast<Address>(player);
    presentation::items::withActor(player, [&] { originalPlayerUpdate(player); });
    actor = before;
}
Address currentActor(void* explicitActor = nullptr) {
    if (explicitActor)
        return reinterpret_cast<Address>(explicitActor);
    if (actor)
        return actor;
    if (viewDepth)
        return participant(runtime::localViewSlot());
    if (scopes.current()) {
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
        const auto desc = reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
            reinterpret_cast<void*>(game()), index,
            dimension < 0 ? source.key.dimension : dimension));
        if (!desc || !at<Address>(desc, 0x10))
            return std::nullopt;
        const auto key = canonicalRoomDestination(index, at<int>(desc, 4), at<int>(desc, 0xc));
        if (!key)
            return std::nullopt;
        return Key{(*key)[0], (*key)[1]};
    };
    if (scopes.current() == &source || (index != -100 && index != -101))
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
           bool animateDeparture = true, int animation = 0,
           std::optional<Vec2> landing = std::nullopt, RoomRouting routing = RoomRouting::native) {
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
    if (!runtime::allowRoomEntry(slotOf(player), it->second->key.dimension, it->second->key.index,
                                 key.dimension, key.index, teleport))
        return false;
    if (std::any_of(pending.begin(), pending.end(),
                    [player](const auto& r) { return r.player == player; }))
        return true;
    if (!teleport && door >= 0 && door < 8 && key.dimension == it->second->key.dimension) {
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        const auto targetDesc =
            reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
                reinterpret_cast<void*>(game()), key.index, key.dimension));
        if (targetDesc && at<Address>(targetDesc, 0x10)) {
            std::array<int, 8> neighbors;
            neighbors.fill(-1);
            for (int slot = 0; slot < 8; ++slot) {
                const int index = at<int>(targetDesc, 0x1c + slot * 4);
                if (index < 0 || index >= 169)
                    continue;
                const auto neighbor =
                    reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
                        reinterpret_cast<void*>(game()), index, key.dimension));
                if (neighbor && at<Address>(neighbor, 0x10))
                    neighbors[slot] = at<int>(neighbor, 4);
            }
            const int resolved = resolveEntranceDoor(door, it->second->key.index, neighbors);
            if (resolved != door)
                logger("room_entry_resolved slot=" + std::to_string(slotOf(player)) + " from=" +
                       std::to_string(it->second->key.index) + " to=" + std::to_string(key.index) +
                       " hint=" + std::to_string(door) + " entry=" + std::to_string(resolved));
            door = resolved;
        }
    }
    pending.push_back({player, key, door, teleport, animateDeparture, animation, landing, routing});
    if (teleport && animateDeparture) {
        using Animate = void(__attribute__((thiscall))*)(void*, bool);
        for (auto p : controlledActors(player))
            engine<Animate>(j460::entry::playerAnimateTeleport)(reinterpret_cast<void*>(p), true);
    }
    return true;
}
void __attribute__((fastcall)) transition(void* g, void*, int index, int direction, int animation,
                                          void* player, int dimension) {
    if (!enabled || transferring) {
        originalTransition(g, index, direction, animation, player, dimension);
        return;
    }
    const auto manager = at<Address>(image, j460::globals::manager);
    if (!runtime::replica() && index == -10 && direction == -1 && animation == 1 && !player &&
        dimension == -1 && at<int>(game(), 0) == 13 && at<int>(game(), 4) == 1 &&
        at<bool>(manager, 0x21618) && at<int>(manager, 0x2161c) == 25) {
        pendingDogma = at<Address>(game(), 0x18300);
        return;
    }
    const auto who = currentActor(player);
    if (!runtime::replica() && !player && scopes.current() &&
        scopes.current()->key.dimension == 0) {
        const auto source = scopes.current();
        const auto list = source->pointer + 0x1258;
        bool transfer = compat::bosses::rotgutReturn(
            source->key.index, index, at<int>(game(), 0x18328), direction, animation, dimension);
        for (unsigned i = 0; !transfer && i < at<unsigned>(list, 12); ++i) {
            const auto entity = at<Address>(at<Address>(list, 4), i * 4);
            transfer = compat::bosses::rotgutSwallow(index, direction, animation, dimension,
                                                     at<unsigned>(entity, 0x28),
                                                     at<unsigned>(entity, 0x2c));
        }
        if (transfer) {
            // Both swallowing AI and the stomach return run with the room
            // roster, outside Player::Update. Other rooms keep running.
            for (const auto head : participants) {
                const auto found = location.find(head);
                if (found != location.end() && found->second == source &&
                    (connectedMask & (1u << slotOf(head))))
                    if (!queue(head, index, dimension, -1, false, false, animation))
                        runtime::abort("Cannot transfer Rotgut's players");
            }
            return;
        }
    }
    if (!runtime::replica() &&
        compat::items::deathCertificateTransfer(animation, at<int>(game(), 0x1830c), dimension)) {
        // Game::EnterDeathCertificate and its Game::Update return both pass a
        // null player. The latter runs outside Player::Update, so resolving a
        // current actor would reject the native return and strand the party.
        for (const auto head : participants)
            if (connectedMask & (1u << slotOf(head)))
                if (!queue(head, index, dimension, -1, false, false, animation))
                    runtime::abort("Cannot transfer the Death Certificate party");
        return;
    }
    const bool teleport = animation == 3 || animation == 11 || animation == 16;
    if (!runtime::replica() && who)
        if (auto it = location.find(who);
            it != location.end() &&
            compat::items::deathCertificateTeleport(animation, it->second->key.dimension)) {
            // The card's ordinary-floor index can have no annex descriptor.
            // Resolve within the annex, falling back to its native entry.
            auto target = destination(*it->second, index, 2);
            if (!target || target->dimension != 2)
                target = destination(*it->second, 80, 2);
            if (!target || !queue(who, target->index, 2, -1, true))
                runtime::abort("Cannot resolve the Death Certificate teleport");
            return;
        }
    if (runtime::replica()) {
        if (!remoteCommand(who, index, dimension, teleport))
            logger("mod_room_command=REJECTED local_actor_unresolved");
        return;
    }
    if (animation == 12 && who) {
        if (rewind::request(slotOf(who)))
            return;
        const auto entry = location.find(who);
        const auto room = entry != location.end() ? entry->second : nullptr;
        const auto source = at<Address>(game(), 0x18300);
        if (room && !room->replicaShell && room->pointer == source &&
            compat::routes::hourglassHomeSource(at<int>(game(), 0), at<int>(game(), 4),
                                                at<int>(game(), 0x269c8), at<int>(game(), 0x18304),
                                                at<int>(game(), 0x182d0), at<bool>(source, 1))) {
            // A native first-room Home use can precede every checkpoint. Its
            // stage hook only queues departure, so the current Scope stays
            // valid. Do not let an empty buffer enter ordinary rewind code.
            const bool hadStage = pendingStage.has_value();
            originalTransition(g, index, direction, animation, player, dimension);
            if (!hadStage && pendingStage &&
                compat::routes::homeTransition(pendingStage->same, pendingStage->animation))
                pendingStage->player = who;
        }
        return;
    }
    // Native item revivals (Dead Cat, Collar, Ankh, 1up) hide the actor until
    // RoomTransition::ChangeRoom restores visibility. Our per-actor transfer
    // bypasses that process-wide screen, including when the previous room is
    // already the actor's current room.
    if (compat::items::revivalTransition(animation) && who)
        pendingItemRevival.insert(slotOf(who));
    // StartRoomTransition normally initializes the Blue Key encounter before
    // switching rooms. Keep its native descriptor/door rules in this scope.
    if (who &&
        compat::items::blueRoomTransition(animation, at<int>(game(), j460::layout::game::dimension),
                                          dimension) &&
        engine::items::initializeBlueRoom(g, at<int>(game(), j460::layout::game::roomIndex), index,
                                          direction))
        index = compat::items::blueRoomIndex;
    const int leave = at<int>(game(), 0x18318);
    const auto mirrorEntry = compat::routes::mirrorEntrance(animation, leave);
    int enter =
        mirrorEntry.value_or(leave >= 0 && leave < 8 ? (leave % 4 + 2) % 4 + (leave / 4) * 4 : -1);
    if (enter >= 0 && !mirrorEntry) {
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        const auto target = reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
            reinterpret_cast<void*>(game()), index, dimension));
        if (target)
            for (int slot = 0; slot < 8; ++slot) {
                const int neighbor = at<int>(target, 0x1c + slot * 4);
                if (neighbor < 0 || neighbor >= 169 || slot % 4 != (leave % 4 + 2) % 4)
                    continue;
                const auto source =
                    reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
                        reinterpret_cast<void*>(game()), neighbor, dimension));
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
    if (!queue(who, index, dimension, teleport ? -1 : enter, teleport, animation == 3, animation))
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
    if (rewind::captureStage(same, animation))
        return;
    if (!enabled) {
        originalStage(g, same, animation, player);
        return;
    }
    if (runtime::replica())
        return;
    // A floor transaction has precedence over room transfers in the same tick.
    // The first actor in deterministic room-update order owns the transaction.
    if (!pendingStage)
        pendingStage =
            StageRequest{same, animation, currentActor(player), at<int>(game(), 0x18304)};
}
void __cdecl rKey() {
    if (!enabled) {
        originalRKey();
        return;
    }
    // J460's R Key timer calls TriggerRKey directly. Defer it until the room
    // scope is gone so its native cleanup sees the complete co-op roster.
    if (!runtime::replica())
        pendingRestart = 1;
}
void __attribute__((fastcall)) victoryLap(void* g, void*) {
    if (!enabled) {
        originalVictoryLap(g);
        return;
    }
    if (runtime::challengeActive())
        return;
    if (!runtime::replica())
        pendingRestart = 2;
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
    engine<RoomCall>(j460::entry::ambushDestroyWaveQueue)(&room.ambush.pendingWaves);
    using AssignImage = void*(__attribute__((thiscall))*)(void*, const void*);
    const std::array<Address, 2> emptyImage{};
    for (auto& handle : room.images)
        engine<AssignImage>(j460::entry::roomAssignLightTexture)(&handle, &emptyImage);
    release(room.scratch.begin, room.scratch.capacity - room.scratch.begin);
    room.scratch = {};
    if (room.owned) {
        engine<RoomCall>(j460::entry::engineRoomsRoomCall_3e9ba0)(
            reinterpret_cast<void*>(room.pointer));
        release(room.pointer, 0x7898);
    }
}
using LuaFn = int(__cdecl*)(lua_State*);
isaac::lua::API lua{};
int dealChances(lua_State* L) {
    if (!lua.getTop(L)) {
        lua.pushNumber(L, engine<DealTotal>(j460::entry::roomGetDevilRoomChance)(
                              reinterpret_cast<void*>(at<Address>(game(), 0x18300))));
        // Use the same detours/return ABI as the actual HUD and room generator.
        lua.pushNumber(
            L, queryAngelShare(reinterpret_cast<void*>(image + j460::entry::dealAngelShare)));
        return 2;
    }
    const auto total = lua.checkNumber(L, 1), angel = lua.checkNumber(L, 2);
    const bool valid = enabled && runtime::replica() && std::isfinite(total) && total >= 0 &&
                       total <= std::numeric_limits<float>::max() && std::isfinite(angel) &&
                       angel >= 0 && angel <= 1;
    if (valid)
        replicaDeals = DealChances{static_cast<float>(total), static_cast<float>(angel)};
    lua.pushBoolean(L, valid);
    return 1;
}
int resetDealChances(lua_State*) {
    replicaDeals.reset();
    return 0;
}
int pickupPrice(lua_State* L) {
    auto pickupWrapper = static_cast<Address*>(lua.toUserdata(L, 1));
    auto playerWrapper = static_cast<Address*>(lua.toUserdata(L, 2));
    if (!enabled || !pickupWrapper || !playerWrapper || lua.rawLength(L, 1) != 8 ||
        lua.rawLength(L, 2) != 8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto pickup = pickupWrapper[1] - 0x48, player = playerWrapper[1] - 0x48;
    if (at<unsigned>(pickup, 0x28) != 5 || at<unsigned>(player, 0x28) != 1 ||
        !at<bool>(pickup, 0x172) || !at<bool>(player, 0x172)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto room = findRoom(player);
    if (!room || room->replicaShell || at<int>(room->pointer, 8) != 14) {
        lua.pushBoolean(L, false);
        return 1;
    }
    Scope scope(*room, {player}, false);
    using Price = int(__attribute__((thiscall))*)(void*, int, int, int, int);
    using Discount = int(__attribute__((thiscall))*)(void*, int, int, int);
    const auto base = engine<Price>(j460::entry::roomPickupPrice)(
        reinterpret_cast<void*>(room->pointer), at<int>(pickup, 0x2c), at<int>(pickup, 0x30),
        at<int>(pickup, 0x53c), 0);
    const auto price = engine<Discount>(j460::entry::roomDiscountedPrice)(
        reinterpret_cast<void*>(room->pointer), at<int>(pickup, 0x53c), base, 0);
    lua.pushInteger(L, price);
    return 1;
}
int pillState(lua_State* L) {
    try {
        // Game::GetItemPool returns Game + 0x1a740. GetPillEffect reads
        // its 15 color assignments at 0x7a4; Identify/IsPillIdentified mask
        // horse-pill colors and access the 15 identification bytes at 0x7e0.
        const auto pool = game() + 0x1a740;
        std::array<int, 15> effects;
        std::array<unsigned char, 15> known;
        const bool applying = lua.getTop(L) != 0;
        if (applying) {
            if (!enabled || !runtime::replica())
                throw std::runtime_error("Only replicas restore pill state");
            std::size_t size = 0;
            const auto bytes = lua.checkString(L, 1, &size);
            lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
            for (unsigned i = 0; i < effects.size(); ++i) {
                effects[i] = static_cast<int>(r.u32());
                known[i] = r.u8();
                if (effects[i] < -1 || effects[i] >= 4096 || known[i] > 1)
                    throw std::runtime_error("Invalid pill state");
            }
            r.finish();
            for (unsigned i = 0; i < effects.size(); ++i) {
                at<int>(pool, 0x7a4 + i * 4) = effects[i];
                at<unsigned char>(pool, 0x7e0 + i) = known[i];
            }
            lua.pushBoolean(L, true);
        } else {
            lan::Writer w(lan::Message::world);
            for (unsigned i = 0; i < effects.size(); ++i) {
                w.u32(at<int>(pool, 0x7a4 + i * 4));
                w.u8(at<bool>(pool, 0x7e0 + i));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
        }
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
bool adopt() {
    if (enabled || scopes.depth())
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
    room->clock.reset(at<int>(game(), j460::layout::game::frame));
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
    if (scopes.depth() || (!room && (enabled || slot < 0 ||
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
int moveParticipant(lua_State* L, RoomRouting routing, bool animateDeparture) {
    const auto slot = lua.checkInteger(L, 1), index = lua.checkInteger(L, 2),
               dimension = lua.checkInteger(L, 3);
    lua.pushBoolean(L, !runtime::replica() && slot >= 0 && slot < 4 && participant(slot) &&
                           (connectedMask & (1u << slot)) && index >= -20 && index < 169 &&
                           dimension >= 0 && dimension <= 2 &&
                           queue(participant(slot), index, dimension, -1, true, animateDeparture, 0,
                                 std::nullopt, routing));
    return 1;
}
int integrationMove(lua_State* L) {
    return moveParticipant(L, RoomRouting::native, true);
}
int teleportToRoom(lua_State* L) {
    // A cancellable command must not leave the actor in TeleportOut while queued.
    return moveParticipant(L, RoomRouting::resolved, false);
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
    const auto all = values(scopes.teamRoster() ? *scopes.teamRoster() : roster());
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
    if (runtime::replica() || scopes.depth() || !room || !(connectedMask & (1u << slot))) {
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
    lua.pushBoolean(L, enabled && !resumeStage && !pendingStage && !pendingRestart);
    return 1;
}
int beginRKey(lua_State* L) {
    const bool ready = runtime::replica() && enabled && !scopes.depth();
    if (ready)
        pendingRestart = 1;
    lua.pushBoolean(L, ready);
    return 1;
}
int beginVictoryLap(lua_State* L) {
    const bool ready =
        runtime::replica() && enabled && !scopes.depth() && !runtime::challengeActive();
    if (ready)
        pendingRestart = 2;
    lua.pushBoolean(L, ready);
    return 1;
}
int chestEnding(lua_State* L) {
    int ending = -1;
    if (enabled && game()) {
        // Match the native departure decision's complete roster while retaining
        // the caller's room. Borrowed roster scope restores itself before return.
        TeamScope team;
        using ChestEnding = int(__stdcall*)(bool);
        ending = engine<ChestEnding>(j460::entry::gameGetChestEnding)(false);
    }
    lua.pushInteger(L, ending);
    return 1;
}
int beginCinematic(lua_State* L) {
    const bool ready = runtime::replica() && enabled && !scopes.depth() &&
                       at<int>(game(), 0) == 13 && at<int>(game(), 4) == 1;
    if (ready)
        pendingDogma = at<Address>(game(), 0x18300);
    lua.pushBoolean(L, ready);
    return 1;
}
int beginFloor(lua_State* L) {
    const auto same = lua.checkInteger(L, 1), animation = lua.checkInteger(L, 2);
    const auto sourceRoom = lua.checkInteger(L, 3);
    const auto head = participant(runtime::localViewSlot());
    const bool ready = runtime::replica() && enabled && !scopes.depth() && head && !pendingStage &&
                       (same == 0 || same == 1) && animation >= 0 && animation <= 6 &&
                       sourceRoom >= -20 && sourceRoom < 169;
    if (ready) {
        pendingStage = StageRequest{same != 0, static_cast<int>(animation), head,
                                    static_cast<int>(sourceRoom)};
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
        engine<RoomCall>(j460::entry::engineRoomsRoomCall_3e9400)(
            reinterpret_cast<void*>(room->pointer));
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
            const auto desc = reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
                reinterpret_cast<void*>(game()), index, dimension));
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
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
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
int roomWaterCurrent(lua_State* L) {
    const auto x = lua.checkNumber(L, 1), y = lua.checkNumber(L, 2);
    const auto room = scopes.current();
    const bool valid = enabled && runtime::replica() && room && !room->replicaShell &&
                       std::isfinite(x) && std::isfinite(y) && x * x + y * y <= 1.000001;
    if (valid) {
        // J460 Room::GetWaterCurrent exposes these two floats but has no Lua
        // setter. Replica layouts omit the spawn marker that initializes them.
        // Restore the room vector before its native ambient-effect update.
        at<float>(room->pointer, 0x7460) = static_cast<float>(x);
        at<float>(room->pointer, 0x7464) = static_cast<float>(y);
    }
    lua.pushBoolean(L, valid);
    return 1;
}
int roomLayout(lua_State* L) {
    try {
        if (lua.getTop(L) == 0 || lua.getTop(L) == 2) {
            using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
            const int dimension = lua.getTop(L) ? lua.checkInteger(L, 2) : at<int>(game(), 0x1830c);
            const int index = lua.getTop(L) ? lua.checkInteger(L, 1) : at<int>(game(), 0x18304);
            const auto desc =
                lua.getTop(L)
                    ? reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
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
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
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
        if (!validLayoutIndices(key.dimension, key.index, gridIndex, listIndex) ||
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
        const auto desc =
            key.index >= 0 ? game() + 0x14 + listIndex * 0xb8
                           : reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
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
        engine<RoomCall>(j460::entry::minimapCache)(reinterpret_cast<void*>(g + offset));
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
int actorPockets(lua_State* L) {
    try {
        auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
        if (!wrapper || lua.rawLength(L, 1) != 8 || !wrapper[1])
            throw std::runtime_error("Invalid actor pocket wrapper");
        const auto player = wrapper[1] - 0x48;
        const auto all = values(scopes.teamRoster() ? *scopes.teamRoster() : roster());
        if (std::find(all.begin(), all.end(), player) == all.end() ||
            at<unsigned>(player, 0x28) != 1)
            throw std::runtime_error("Pocket state requires a listed player");
        if (lua.getTop(L) == 1) {
            lan::Writer w(lan::Message::world);
            for (unsigned i = 0; i < 4; ++i) {
                w.u32(at<unsigned>(player, 0x17a0 + i * 8));
                w.u32(at<unsigned>(player, 0x17a4 + i * 8));
            }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas restore pocket state");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        std::array<std::array<unsigned, 2>, 4> pockets;
        for (auto& value : pockets) {
            value = {r.u32(), r.u32()};
            if (value[0] > 65535 || value[1] > 2 ||
                (value[1] == 2 && (value[0] < 3 || value[0] > 4)))
                throw std::runtime_error("Invalid ordered pocket state");
        }
        r.finish();
        // Only scalar pocket ID/kind records move. The active-item objects,
        // item acquisition and gameplay remain with inventory reconciliation.
        for (unsigned i = 0; i < pockets.size(); ++i) {
            at<unsigned>(player, 0x17a0 + i * 8) = pockets[i][0];
            at<unsigned>(player, 0x17a4 + i * 8) = pockets[i][1];
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int actorCraftingBag(lua_State* L) {
    try {
        auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
        if (!wrapper || lua.rawLength(L, 1) != 8 || wrapper[1] < 0x48)
            throw std::runtime_error("Invalid crafting bag actor wrapper");
        const auto player = wrapper[1] - 0x48;
        const auto all = values(scopes.teamRoster() ? *scopes.teamRoster() : roster());
        if (std::find(all.begin(), all.end(), player) == all.end() ||
            at<unsigned>(player, 0x28) != 1)
            throw std::runtime_error("Crafting bag state requires a listed player");
        if (lua.getTop(L) == 1) {
            lan::Writer w(lan::Message::world);
            for (unsigned i = 0; i < 8; ++i)
                w.u8(at<std::uint8_t>(player, 0x1f44 + i));
            w.u32(at<unsigned>(player, 0x1f4c));
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas restore crafting bag state");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 2, &size);
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        compat::items::CraftingBagState value;
        for (auto& material : value.materials)
            material = r.u8();
        value.preview = r.u32();
        r.finish();
        if (!compat::items::validCraftingBagState(value))
            throw std::runtime_error("Invalid crafting bag state");
        bool changed = at<unsigned>(player, 0x1f4c) != value.preview;
        for (unsigned i = 0; i < value.materials.size(); ++i)
            changed |= at<std::uint8_t>(player, 0x1f44 + i) != value.materials[i];
        if (changed) {
            for (unsigned i = 0; i < value.materials.size(); ++i)
                at<std::uint8_t>(player, 0x1f44 + i) = value.materials[i];
            at<unsigned>(player, 0x1f4c) = value.preview;
            // Vanilla acquisition marks only this actor's owned HUD cache dirty.
            // Repeated snapshots leave its native animation/cache intact.
            using GetHUD = void*(__attribute__((thiscall))*)(void*);
            const auto hud = reinterpret_cast<Address>(
                engine<GetHUD>(j460::entry::engineRoomsGetHUD)(reinterpret_cast<void*>(game())));
            for (unsigned i = 0; i < 8; ++i) {
                const auto part = hud + i * 0x6dc;
                if (at<Address>(part, 0) == player)
                    at<bool>(part, 0x6ad) = true;
            }
        }
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int actorCompanions(lua_State* L) {
    try {
        if (!runtime::replica() || !enabled || scopes.depth())
            throw std::runtime_error("Only an idle replica restores companion actors");
        struct Companion {
            unsigned id, index, parent, controller, kind, variant;
            int babySkin;
        };
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 1, &size);
        lan::Reader reader({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto count = reader.u8();
        if (count > 60)
            throw std::runtime_error("Too many companion actors");
        std::vector<Companion> desired;
        std::set<unsigned> ids, indices;
        for (unsigned i = 0; i < count; ++i) {
            Companion value{reader.u32(),
                            reader.u8(),
                            reader.u8(),
                            reader.u8(),
                            reader.u16(),
                            reader.u16(),
                            static_cast<std::int16_t>(reader.u16())};
            if (!value.id || value.index >= 64 || value.parent >= value.index ||
                value.controller < 1 || value.controller > 4 || value.variant > 1 ||
                value.babySkin < -1 || value.babySkin > j460::layout::player::lastBabySkin ||
                !ids.insert(value.id).second || !indices.insert(value.index).second)
                throw std::runtime_error("Invalid companion actor identity");
            desired.push_back(value);
        }
        reader.finish();
        if (!count && replicaCompanions.empty()) {
            lua.pushBoolean(L, true);
            return 1;
        }
        std::sort(desired.begin(), desired.end(),
                  [](const auto& a, const auto& b) { return a.index < b.index; });
        auto all = values(roster());
        for (auto it = replicaCompanions.begin(); it != replicaCompanions.end();) {
            if (ids.contains(it->first)) {
                ++it;
                continue;
            }
            const auto body = it->second;
            if (std::find(all.begin(), all.end(), body) != all.end()) {
                const auto room = findRoom(body);
                if (!room)
                    throw std::runtime_error("Companion room is missing");
                {
                    Scope scope(*room, all);
                    using Remove = void(__attribute__((thiscall))*)(void*, void*, bool);
                    engine<Remove>(j460::entry::playerManagerRemovePlayer)(
                        reinterpret_cast<void*>(game() + j460::layout::game::players),
                        reinterpret_cast<void*>(body), false);
                }
                location.erase(body);
                all = values(roster());
            }
            it = replicaCompanions.erase(it);
        }
        for (const auto& value : desired) {
            if (value.parent >= all.size())
                throw std::runtime_error("Companion owner is missing");
            const auto parent = all[value.parent];
            if (at<unsigned>(parent, j460::layout::player::controller) != value.controller)
                throw std::runtime_error("Companion controller differs from its owner");
            const auto room = findRoom(parent);
            if (!room)
                throw std::runtime_error("Companion owner has no room");
            Address body = 0;
            if (const auto found = replicaCompanions.find(value.id);
                found != replicaCompanions.end() &&
                std::find(all.begin(), all.end(), found->second) != all.end())
                body = found->second;
            // Continue/rejoin can already contain the native parented body.
            if (!body && value.index < all.size()) {
                const auto candidate = all[value.index];
                if (at<Address>(candidate, j460::layout::entity::parent) == parent &&
                    at<unsigned>(candidate, j460::layout::player::controller) == value.controller &&
                    at<unsigned>(candidate, j460::layout::player::type) == value.kind)
                    body = candidate;
            }
            if (!body) {
                const auto view = findRoom(participant(runtime::localViewSlot()));
                if (!view || view->replicaShell)
                    throw std::runtime_error("Companion creation requires a loaded local room");
                {
                    Scope scope(*view, all);
                    using Spawn = void*(__attribute__((thiscall))*)(void*, int);
                    body = reinterpret_cast<Address>(engine<Spawn>(j460::entry::engineInputSpawn)(
                        reinterpret_cast<void*>(game() + j460::layout::game::players), 0));
                    if (!body)
                        throw std::runtime_error("Cannot allocate companion actor");
                    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
                    engine<Assign>(j460::entry::engineRoomsAssign)(reinterpret_cast<void*>(body),
                                                                   value.controller, false);
                    using AssignPtr = void*(__attribute__((thiscall))*)(void*, void*);
                    engine<AssignPtr>(j460::entry::entityPtrAssignTwin)(
                        reinterpret_cast<void*>(body + j460::layout::entity::parent),
                        reinterpret_cast<void*>(parent));
                    // Initialize a neutral native body, then restore its display
                    // form. Initializing a gameplay character here would create
                    // another Soul/twin or reroll starting items on the replica.
                    engine<RoomCall>(j460::entry::engineInputInitialize)(
                        reinterpret_cast<void*>(body));
                    at<unsigned>(body, j460::layout::player::type) = value.kind;
                    at<unsigned>(body, j460::layout::entity::variant) = value.variant;
                }
                if (view != room)
                    moveEntity(body, *view, *room);
                location[body] = room;
                all = values(roster());
            }
            // Inventory cache evaluation recognizes native baby companions by
            // both variant and skin. Establish that identity before any parent
            // inventory setter can decide to allocate a second companion.
            at<int>(body, j460::layout::player::babySkin) = value.babySkin;
            replicaCompanions[value.id] = body;
            const auto existing = std::find(all.begin(), all.end(), body);
            if (existing == all.end() || value.index >= all.size())
                throw std::runtime_error("Companion roster index is missing");
            all.erase(existing);
            all.insert(all.begin() + value.index, body);
        }
        assign(roster(), all);
        for (unsigned i = 0; i < all.size(); ++i)
            at<unsigned>(all[i], j460::layout::player::index) = i;
        participants = logicalPlayers();
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int actorForm(lua_State* L) {
    const auto index = lua.checkInteger(L, 1), desired = lua.checkInteger(L, 2);
    const auto controller = lua.getTop(L) >= 3 ? lua.checkInteger(L, 3) : -1;
    const auto all = values(roster());
    if (!runtime::replica() || !enabled || scopes.depth() || index < 0 ||
        static_cast<std::size_t>(index) > all.size() || (!compat::characters::lazarus(desired))) {
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
            if ((!compat::characters::lazarus(kind)) || at<int>(owner, 0x1618) != controller ||
                !room || !backup || at<unsigned>(backup, 0x28) != 1 ||
                at<int>(backup, 0x13c0) != desired || at<Address>(backup, 0x1e6c) != owner ||
                std::find(all.begin(), all.end(), backup) != all.end())
                continue;
            using AssignPtr = void*(__attribute__((thiscall))*)(void*, void*);
            using AddPlayer = void(__attribute__((thiscall))*)(void*, void*);
            {
                Scope scope(*room, all);
                engine<AssignPtr>(j460::entry::entityPtrAssignTwin)(
                    reinterpret_cast<void*>(owner + 0x1e68), reinterpret_cast<void*>(backup));
                engine<AssignPtr>(j460::entry::entityPtrAssignTwin)(
                    reinterpret_cast<void*>(backup + 0x1e68), reinterpret_cast<void*>(owner));
                at<Address>(owner, 0x1e6c) = at<Address>(backup, 0x1e6c) = 0;
                at<int>(backup, 0x1618) = controller;
                at<bool>(backup, 0x170) = at<bool>(backup, 0x172) = true;
                at<Vec2>(backup, 0x33c) = at<Vec2>(owner, 0x33c);
                engine<AddPlayer>(j460::entry::playerManagerAddExistingPlayer)(
                    reinterpret_cast<void*>(game() + 0x1baa8), reinterpret_cast<void*>(backup));
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
    if (!room || (!compat::characters::lazarus(kind))) {
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
        replaced = engine<Replace>(j460::entry::playerManagerReplacePlayer)(
            reinterpret_cast<void*>(game() + 0x1baa8), reinterpret_cast<void*>(old),
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
        engine<RoomCall>(ghost ? j460::entry::replicaMorphToCoopGhost
                               : j460::entry::replicaRevivePlayerGhost)(
            reinterpret_cast<void*>(all[index]));
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
            lua.pushLString(L, reinterpret_cast<const char*>(bytes.bytes.data() + 1),
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
        auto path = presentation::readLaserPath(bytes);
        if (lua.getTop(L) > 2) {
            if (lua.getTop(L) != 4)
                throw std::runtime_error("Laser render offset requires two coordinates");
            presentation::translateLaserPath(path, static_cast<float>(lua.checkNumber(L, 3)),
                                             static_cast<float>(lua.checkNumber(L, 4)));
        }
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
        !engine<IsClear>(j460::entry::roomIsClear)(reinterpret_cast<void*>(room))) {
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
    const auto address = reinterpret_cast<Address>(entity);
    if (runtime::replica() &&
        !presentation::localAmbientEffect(at<unsigned>(address, 0x28), at<unsigned>(address, 0x2c),
                                          at<unsigned>(address, 0x30)))
        return;
    const auto entry = at<Address>(at<Address>(address, 0), 0xc);
    entityUpdates.at(entry)(entity);
}
bool interceptReplicaEntities(Room& room) {
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
                return false;
            }
            entityUpdates.emplace(entry, original);
        }
    }
    return true;
}
} // namespace

bool finalCombat() {
    if (!enabled || !scopes.current() || runtime::replica())
        return false;
    const auto room = scopes.current()->pointer;
    for (std::size_t offset : {0x20u, 0x40u, 0x70u}) {
        const auto list = room + 0x1218 + offset;
        for (unsigned i = 0; i < at<unsigned>(list, 12); ++i) {
            const auto entity = at<Address>(at<Address>(list, 4), i * 4);
            // Nighttime Home's TV spawns and immediately updates Dogma inside
            // its own update. Gather before that call, including debug damage,
            // so the original intro starts with the complete room roster.
            if (compat::bosses::finalCombat(at<int>(game(), 0), at<int>(game(), 4),
                                            at<unsigned>(entity, 0x28), at<unsigned>(entity, 0x2c),
                                            runtime::difficulty()))
                return true;
        }
    }
    return false;
}
bool update(void* pointer, RoomCall original) {
    if (!enabled || transferring)
        return false;
    if (scopes.depth()) {
        // Snapshot reconciliation calls Room::Update to reclaim removed
        // allocations before spawning replacements. On rejoin, beforeStart
        // cleared the intercepts and no normal room tick has installed them
        // yet. Every scoped replica update must isolate gameplay first.
        if (runtime::replica()) {
            auto room = scopes.current();
            if (!room || room->pointer != reinterpret_cast<Address>(pointer)) {
                runtime::abort("Replica cleanup escaped its room scope");
                return true;
            }
            if (!interceptReplicaEntities(*room))
                return true;
        }
        return false;
    }
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
        if (!runtime::replica() && (soundAudience() & connectedMask) != connectedMask &&
            finalCombat()) {
            // Terminal encounters own global cinematics and control locks.
            // Complete the team arrival before advancing their native AI.
            gatherForTransition([] {});
            continue;
        }
        if (!runtime::replica()) {
            const bool paused = presentation::roomPaused();
            room->clock.advance(at<int>(game(), j460::layout::game::frame), paused,
                                at<int>(room->pointer, j460::layout::room::enteredFrame));
            if (paused)
                continue;
        }
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
            engine<Lerp>(j460::entry::colorModStateLerp)(reinterpret_cast<void*>(game() + 0x676b8),
                                                         reinterpret_cast<void*>(game() + 0x676d0),
                                                         reinterpret_cast<void*>(game() + 0x676e8));
        }
        if (runtime::replica() && !interceptReplicaEntities(*room))
            return true;
        original(reinterpret_cast<void*>(room->pointer));
        if (!runtime::replica() && (soundAudience() & connectedMask) != connectedMask &&
            finalCombat())
            gatherForTransition([] {});
        ++room->updates;
    }
    return true;
}
bool half(void (*original)()) {
    if (!enabled || scopes.depth() || transferring)
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
    if (!enabled || scopes.depth() || slot < 0 || slot >= 4)
        return false;
    auto room = findRoom(participant(slot));
    if (!room)
        return false;
    withView([&] {
        audio::present();
        presentation::pickup_preview::prepare();
        presentation::items::withScreen(
            [&] { combat_feedback::withPresentation(room->pointer, [&] { original(g); }); });
    });
    return true;
}
void presentCamera() {
    if (!enabled || scopes.depth() || transferring || !runtime::replica())
        return;
    const auto head = participant(runtime::localViewSlot());
    const auto room = findRoom(head);
    if (!room || room->replicaShell)
        return;
    const auto manager = at<Address>(image, j460::globals::manager);
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
    if (!enabled || !transferring || !scopes.current())
        return false;
    const auto it = location.find(participant(runtime::localViewSlot()));
    return it == location.end() || it->second != scopes.current();
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
    auto players = values(scopes.teamRoster() ? *scopes.teamRoster() : roster());
    if (localPlayersOnly)
        std::erase_if(players, [&](Address p) { return at<int>(p, 0x1618) != slot + 1; });
    std::stable_partition(players.begin(), players.end(),
                          [&](Address p) { return at<int>(p, 0x1618) == slot + 1; });
    if (!room) {
        ViewRoster view(players);
        pause_menu::ViewScope pauseView(image, slot);
        draw();
        return;
    }
    Scope scope(*room, players, false);
    pause_menu::ViewScope pauseView(image, slot);
    draw();
}
bool checkpointReady() {
    return enabled && !scopes.depth() && !resumeStage && !pendingStage && !pendingRestart &&
           loaded.size() == 1;
}
bool stateReady() {
    return enabled && !scopes.depth() && !resumeStage && !pendingStage && !pendingRestart;
}
bool viewReady() {
    return enabled && !transferring && !resumeStage && !pendingStage && !pendingRestart;
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
int floorSourceRoom() {
    return floorSource.room(at<int>(game(), 0x18304));
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
    if (!enabled || scopes.depth())
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
    if (!enabled || scopes.depth())
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
            engine<RoomCall>(j460::entry::engineRoomsRoomCall_3e9400)(
                reinterpret_cast<void*>(parked.room->pointer));
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
                clearRoomTransitionTarget(actor);
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
        engine<RoomCall>(j460::entry::engineRoomsRoomCall_5a8620)(
            engine<GetHUD>(j460::entry::engineRoomsGetHUD)(reinterpret_cast<void*>(game())));
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
                engine<Cooldown>(j460::entry::engineRoomsCooldown)(reinterpret_cast<void*>(actor),
                                                                   90);
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
    if (!enabled || scopes.depth() || !room || !(connectedMask & (1u << slot)))
        return false;
    Scope scope(*room, controlledActors(head));
    call();
    return true;
}
bool withRoomPlayers(unsigned slot, const std::function<void()>& call) {
    const auto head = slot < 4 ? participant(slot) : 0;
    const auto room = head ? findRoom(head) : nullptr;
    if (!enabled || scopes.depth() || !room || !(connectedMask & (1u << slot)))
        return false;
    Scope scope(*room);
    call();
    return true;
}
bool gatherForTransition(const std::function<void()>& begin) {
    if (!enabled || runtime::replica() || !scopes.current())
        return false;
    if (!pendingTeamTransition)
        pendingTeamTransition = TeamTransition{scopes.current()->key, begin};
    return true;
}
bool restoreLocations(const std::vector<SavedLocation>& saved) {
    if (!enabled || scopes.depth() || saved.size() != participants.size())
        return false;
    // Apply saved positions to the complete restored roster before parking
    // offline actors. Otherwise their dormant position captures the native
    // Continue spawn point on one machine and the saved point on another.
    const auto mask = connectedMask;
    setConnected(15);
    for (unsigned slot = 0; slot < saved.size(); ++slot) {
        if (runtime::replica() && slot != static_cast<unsigned>(runtime::localViewSlot()))
            continue;
        if (!queue(participants[slot], saved[slot].index, saved[slot].dimension, -1, false, true, 0,
                   std::nullopt, RoomRouting::resolved))
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
namespace {
// Own the per-actor handoff until native entry and all arrival effects finish.
// Native Maze resolution runs before prepare(), so loaded rooms are always
// addressed by the final descriptor and never renamed after initialization.
struct RoomTransfer {
    Request request;
    Room* from;
    Room* to = nullptr;
    bool created = false, protect = false;
    std::vector<Address> actors, companions;
    std::optional<Vec2> landing;

    explicit RoomTransfer(const Request& value)
        : request(value), from(findRoom(value.player)), actors(controlledActors(value.player)) {}

    void leave() {
        auto collect = [&] {
            for (auto player : actors)
                for (auto entity : followers(player, *from))
                    if (std::find(companions.begin(), companions.end(), entity) == companions.end())
                        companions.push_back(entity);
        };
        collect();
        {
            Scope scope(*from, actors);
            for (auto player : actors) {
                if (!preparedDepartures.contains(player))
                    originalLeave(reinterpret_cast<void*>(player), false);
                if (!runtime::replica())
                    engine::items::leaveRoom(reinterpret_cast<void*>(player));
            }
        }
        collect();
    }

    void prepare(std::optional<j460::RoomArrival> resolved = std::nullopt) {
        std::array<std::uint32_t, contextOffsets.size()> nativeContext{};
        if (resolved) {
            const auto final = destination(*from, resolved->index, resolved->dimension);
            if (!final)
                throw std::runtime_error("Native room resolution selected an invalid descriptor");
            // Maze can select another covered cell/entrance of the same large
            // room. Its native redirect flag matters even if the key matches.
            const bool redirected = resolved->redirected || *final != request.destination;
            logger("room_route slot=" + std::to_string(slotOf(request.player)) +
                   " from=" + std::to_string(from->key.index) +
                   " requested=" + std::to_string(request.destination.index) +
                   " actual=" + std::to_string(final->index) +
                   " native_index=" + std::to_string(resolved->index) +
                   " redirected=" + std::to_string(resolved->redirected) +
                   " native_entry=" + std::to_string(resolved->door));
            request.destination = *final;
            if (redirected) {
                request.door = resolved->door;
                request.landing.reset();
            }
            for (unsigned i = 0; i < nativeContext.size(); ++i)
                nativeContext[i] = at<std::uint32_t>(game(), contextOffsets[i]);
        }
        auto found = loaded.find(request.destination);
        created = found == loaded.end() || found->second->replicaShell;
        if (found == loaded.end()) {
            auto room = std::make_unique<Room>();
            room->pointer = reinterpret_cast<Address>(allocate(j460::layout::room::size));
            room->owned = true;
            engine<RoomCall>(j460::entry::engineRoomsRoomCall_3e9400)(
                reinterpret_cast<void*>(room->pointer));
            room->key = request.destination;
            room->context = from->context;
            to = room.get();
            loaded.emplace(request.destination, std::move(room));
        } else {
            to = found->second.get();
            if (to->replicaShell)
                to->context = from->context;
        }
        protect = !created && occupiedCombat(*to, request.player);
        std::optional<std::array<float, 2>> residentPosition;
        if (!created) {
            const auto residents = occupants(*to);
            if (!residents.empty()) {
                const auto position = at<Vec2>(residents.front(), 0x33c);
                residentPosition = {position.x, position.y};
            }
        }
        const auto certificatePosition = compat::items::deathCertificateArrival(
            request.animation, from->key.dimension, to->key.dimension, residentPosition);
        landing = request.landing ? request.landing
                  : certificatePosition
                      ? std::optional<Vec2>{{(*certificatePosition)[0], (*certificatePosition)[1]}}
                      : std::nullopt;
        if (created)
            prepareDepartureMetadata(
                std::span<std::uint32_t, 3>(reinterpret_cast<std::uint32_t*>(to->pointer), 3),
                std::span<const std::uint32_t, 3>(
                    reinterpret_cast<const std::uint32_t*>(from->pointer), 3));
        to->replicaShell = false;
        if (resolved) {
            if (created)
                to->context = nativeContext;
            else {
                // Preserve resident simulation/render state, changing only
                // the native transition's room, dimension, door and map scalars.
                constexpr unsigned transitionScalars = 7;
                std::copy_n(nativeContext.begin(), transitionScalars, to->context.begin());
            }
        }
        if (from == to)
            return;
        for (auto player : actors) {
            moveEntity(player, *from, *to);
            location[player] = to;
        }
        for (auto entity : companions)
            if (!created || at<unsigned>(entity, 0x28) != compat::characters::darkEsau) {
                moveEntity(entity, *from, *to);
                if (at<unsigned>(entity, 0x28) == 867) {
                    using Persistent = void(__attribute__((thiscall))*)(void*, void*);
                    engine<Persistent>(j460::entry::engineRoomsAddPersistent)(
                        reinterpret_cast<void*>(to->pointer + 0x1218),
                        reinterpret_cast<void*>(entity));
                }
            }
    }

    void initialize() {
        if (!created)
            return;
        if (runtime::replica()) {
            if (from->key.dimension != 2 && request.destination.dimension == 2) {
                // Replicas enter from a resolved room view, without
                // Game::EnterDeathCertificate. Its five scalar origin
                // fields are nevertheless consumed by ChangeRoom on
                // return (J460 0x33fd70); preserve the native context.
                at<int>(game(), 0x18900) = from->key.index;
                at<unsigned char>(game(), 0x18904) = from->key.dimension;
                at<int>(game(), 0x18908) = at<int>(game(), 0x18308);
                at<unsigned char>(game(), 0x1890c) = at<int>(game(), 0x18310);
                at<int>(game(), 0x188fc) = at<int>(game(), 0x18318);
            } else if (from->key.dimension == 2 && request.destination.dimension != 2) {
                // The activating player may have been in another
                // normal room. The authority's resolved return wins.
                at<int>(game(), 0x18900) = request.destination.index;
                at<unsigned char>(game(), 0x18904) = request.destination.dimension;
            }
        }
        // Explicit replica/restoration destinations are never re-routed.
        at<int>(game(), j460::layout::game::leaveDoor) = -1;
        at<int>(game(), j460::layout::game::enterDoor) = request.door;
        const auto curseBase = at<std::uint32_t>(game(), j460::layout::game::curses);
        const auto curseSeeds = at<std::uint32_t>(game(), j460::layout::game::seedCurses);
        auto change = [&] {
            j460::withResolvedRoomEntry(
                [&](j460::RoomArrival) {
                    // Explicit transfers suppress LeaveDoor rerouting. Native
                    // resolution can then choose a fallback entrance; restore
                    // the accepted door before Room::Init constructs its exits.
                    if (request.door >= 0 && request.door < 8)
                        at<int>(game(), j460::layout::game::enterDoor) = request.door;
                    return true;
                },
                [&] {
                    originalChange(reinterpret_cast<void*>(game()), request.destination.index,
                                   request.destination.dimension);
                });
        };
        if (runtime::replica() || restoringSavedLocations ||
            request.routing == RoomRouting::resolved)
            j460::withoutRoomCurseRouting(change);
        else
            change();
        logger("room_change requested=" + std::to_string(request.destination.index) +
               " actual=" + std::to_string(at<int>(game(), j460::layout::game::roomIndex)) +
               " curse_base=" + std::to_string(curseBase) +
               " curse_seeds=" + std::to_string(curseSeeds));
    }

    void arrive() {
        // Native Maze may select a covered grid cell of a large room. Keep
        // that entry context, but compare identity through its descriptor.
        const auto actual = destination(*to, at<int>(game(), j460::layout::game::roomIndex),
                                        at<int>(game(), j460::layout::game::dimension));
        if (!actual || *actual != to->key)
            throw std::runtime_error("Native room entry differs from its registered destination");
        if (created) {
            if (!runtime::replica())
                engine<RoomCall>(j460::entry::roomUpdateMusic)(
                    reinterpret_cast<void*>(to->pointer));
            for (auto entity : companions)
                if (at<unsigned>(entity, 0x28) == compat::characters::darkEsau)
                    moveEntity(entity, *from, *to);
        } else {
            // Joining an occupied room must apply the arriving characters'
            // entry effects without reinitializing resident entities.
            for (auto player : actors) {
                clearRoomTransitionTarget(player);
                engine<RoomCall>(j460::entry::engineRoomsRoomCall_3a8350)(
                    reinterpret_cast<void*>(player));
            }
            for (auto entity : companions)
                if (at<unsigned>(entity, 0x28) == 3)
                    engine<RoomCall>(j460::entry::engineRoomsRoomCall)(
                        reinterpret_cast<void*>(entity));
                else if (at<unsigned>(entity, 0x28) == 867) {
                    const auto previousIndex = at<int>(game(), 0x18308);
                    const auto previousDimension = at<int>(game(), 0x18310);
                    at<int>(game(), 0x18308) = from->key.index;
                    at<int>(game(), 0x18310) = from->key.dimension;
                    // Native NPC entry translates the chasing Shadow into
                    // the destination's coordinates, away from the actor.
                    engine<RoomCall>(j460::entry::engineRoomsNPCNewRoom)(
                        reinterpret_cast<void*>(entity));
                    at<int>(game(), 0x18308) = previousIndex;
                    at<int>(game(), 0x18310) = previousDimension;
                }
        }
        arrival(request.player, *to, request.door, companions, protect, landing);
        for (auto player : actors)
            if (player != request.player)
                arrival(player, *to, request.door, {}, protect, landing);
        if (!created && !runtime::replica()) {
            // Native room entry resets each arriving familiar's room-local
            // state after placement, including its delayed follow history.
            // Resident companions must retain their current room behavior.
            for (auto entity : companions)
                if (at<unsigned>(entity, 0x28) == 3)
                    engine<RoomCall>(j460::entry::familiarResetRoomState)(
                        reinterpret_cast<void*>(entity));
        }
        runtime::roomEntered();
        if (created) {
            to->clock.reset(at<int>(game(), j460::layout::game::frame));
            presentation::roomEntered(to->pointer);
        }
        if (!created) {
            // J460's native POST_NEW_ROOM dispatcher (callback 19). A
            // resident room needs the entry notification without Init;
            // local Mod interfaces must not keep the departure descriptor.
            engine<PostUpdate>(j460::entry::luaPostNewRoom)();
        }
        if (request.teleport) {
            using Animate = void(__attribute__((thiscall))*)(void*, bool);
            for (auto p : actors) {
                engine<Animate>(j460::entry::playerAnimateTeleport)(reinterpret_cast<void*>(p),
                                                                    false);
            }
        }
        // The native minecart (animation 19) also disables controls. Only
        // its arriving actors receive the native completion; residents in
        // another room keep their own control and animation state.
        for (auto p : actors)
            completeArrivalControls(request.animation, at<bool>(p, 0x410),
                                    at<int>(game(), 0x26614));
    }

    void run(bool resolve) {
        leave();
        struct NativeTransfer {
            bool previous = transferring;
            Address previousSave = skipSave;
            NativeTransfer() {
                transferring = true;
            }
            ~NativeTransfer() {
                transferring = previous;
                skipSave = previousSave;
            }
        };
        if (resolve) {
            Scope scope(*from, actors);
            at<int>(game(), j460::layout::game::leaveDoor) = -1;
            at<int>(game(), j460::layout::game::enterDoor) = request.door;
            {
                NativeTransfer nativeTransfer;
                j460::withResolvedRoomEntry(
                    [&](j460::RoomArrival resolved) {
                        prepare(resolved);
                        scope.enter(*to);
                        if (request.door >= 0 && request.door < 8)
                            at<int>(game(), j460::layout::game::enterDoor) = request.door;
                        return created;
                    },
                    [&] {
                        originalChange(reinterpret_cast<void*>(game()), request.destination.index,
                                       request.destination.dimension);
                    });
            }
            arrive();
        } else {
            prepare();
            Scope scope(*to, actors);
            {
                NativeTransfer nativeTransfer;
                skipSave = to->pointer;
                initialize();
            }
            arrive();
        }
        canonical();
        logger("room_transfer slot=" + std::to_string(slotOf(request.player)) +
               " from=" + std::to_string(from->key.index) + " to=" + std::to_string(to->key.index) +
               " created=" + std::to_string(created) + " entry=" + std::to_string(request.door) +
               " x=" + std::to_string(at<float>(request.player, 0x33c)) +
               " y=" + std::to_string(at<float>(request.player, 0x340)));
    }
};
} // namespace
void finishFrame() {
    if (scopes.depth())
        return;
    if (enabled)
        actors::forgetRemoved(location, values(roster()));
    if (pendingExit) {
        requestExit(*pendingExit);
        pendingExit.reset();
        return;
    }
    if (resumeStage && !enabled && at<int>(game(), 0x1ba78) == 0 && at<int>(game(), 0x1b83c) == 0) {
        if (adopt()) {
            floorSource.reset();
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
            engine<Movie>(j460::entry::managerShowCutscene)(25, false, 1);
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
            queue(head, transition.room.index, transition.room.dimension, -1, false, false, 0,
                  std::nullopt, RoomRouting::resolved);
        beginTeamTransition = std::move(transition.begin);
    }
    // Transformations may replace the player object while keeping its native
    // controller. Resolve that controller again before dereferencing a head.
    const auto currentParticipants = logicalPlayers();
    participants = currentParticipants;
    if (pendingStage &&
        compat::routes::homeTransition(pendingStage->same, pendingStage->animation)) {
        // Home owns the floor; a simultaneous hourglass cannot consume an old
        // checkpoint and erase the pending native departure in beforeStart.
        rewind::cancelPending();
        pendingRestart = 0;
    }
    if (rewind::executePending())
        return;
    if (pendingRestart == 2) {
        // The host's native confirmation changes Seeds, lap counters, players
        // and the floor directly. Run it once with the complete roster, after
        // scoped room callbacks have finished, on both sides of the barrier.
        runtime::beginStage(false, 0, 2);
        beforeStart();
        resumeStage = true;
        originalVictoryLap(reinterpret_cast<void*>(game()));
        logger("floor_transaction=VICTORY_LAP");
        return;
    }
    if (pendingRestart == 1) {
        // Consume the queued request before checkpointing: stateReady rejects
        // an outstanding restart, just as it rejects a pending stage request.
        pendingRestart = 0;
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
        beforeStart(true);
        resumeStage = true;
        // A Big Chest either changes floors or ends the run. Only the host
        // evaluates that native decision; a terminal chest must not also send
        // a speculative floor event before the reliable ending event. Evaluate
        // with the same complete roster that native departure will use.
        if (!floorSource.begin(request.sourceRoom)) {
            runtime::abort("Invalid native floor source room");
            return;
        }
        using ChestEnding = int(__stdcall*)(bool);
        if (request.animation != 4 || runtime::replica() ||
            engine<ChestEnding>(j460::entry::gameGetChestEnding)(false) == 0)
            runtime::beginStage(request.same, request.animation);
        // Replicas never simulate the chest collector or its grid markers.
        // Use the ordinary floor entry rather than waiting for local markers
        // and re-evaluating the chest against replica unlocks/inventory. J460
        // animation 1 plays Forget Me Now's collectible pickup, not a fade.
        const auto animation = runtime::replica() && request.animation == 4 ? 0 : request.animation;
        logger("floor_transaction=BEGIN same=" + std::to_string(request.same) +
               " received_animation=" + std::to_string(request.animation) + " native_animation=" +
               std::to_string(animation) + " source_room=" + std::to_string(request.sourceRoom));
        originalStage(reinterpret_cast<void*>(game()), request.same, animation,
                      reinterpret_cast<void*>(request.player));
        return;
    }
    setConnected(connectedMask);
    if (!runtime::replica()) {
        std::array<compat::characters::GhostRoomActor, lan::maxPlayers> actors{};
        std::size_t count = 0;
        for (const auto player : participants) {
            const auto room = findRoom(player);
            if (!room)
                continue;
            const auto slot = slotOf(player);
            const auto position = at<Vec2>(player, 0x33c);
            actors[count++] = {slot,
                               room->key.dimension,
                               room->key.index,
                               at<bool>(player, j460::layout::player::coopGhost),
                               (connectedMask & (1u << slot)) != 0,
                               position.x,
                               position.y};
        }
        const auto roster = std::span(actors).first(count);
        for (const auto& actor : roster)
            if (const auto target = compat::characters::ghostFollowTarget(actor, roster))
                queue(participant(actor.slot), target->room, target->dimension, -1, false, true, 0,
                      Vec2{target->x, target->y}, RoomRouting::resolved);
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
            !engine<Finished>(j460::entry::spriteIsFinished)(
                reinterpret_cast<void*>(request.player + 0x48), "")) {
            pending.push_back(request);
            continue;
        }
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        auto desc = reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
            reinterpret_cast<void*>(game()), request.destination.index,
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
        RoomTransfer transfer(request);
        transfer.run(compat::routes::resolveRoomCurse(
            runtime::replica(), restoringSavedLocations || request.routing == RoomRouting::resolved,
            j460::currentCurses()));
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
                engine<Cooldown>(j460::entry::engineRoomsCooldown)(reinterpret_cast<void*>(player),
                                                                   90);
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
    const auto manager = at<Address>(image, j460::globals::manager);
    at<bool>(manager, 0x4b284) = save;
    at<int>(manager, 0x4b28c) = 2;
    using Transition = void(__attribute__((thiscall))*)(void*, int);
    engine<Transition>(j460::entry::engineRoomsTransition_60f550)(
        reinterpret_cast<void*>(manager + 0x4b290), -1);
    at<bool>(manager, 0x4b288) = true;
}
void finishChallenge() {
    // LAN challenges keep Game::Challenge at zero: use the original fade/menu
    // flow while skipping native challenge unlocks. Existing save guards cover
    // FinishChallenge's attempt to remove the single-player Continue file.
    reinterpret_cast<RoomCall>(image +
                               j460::entry::gameFinishChallenge)(reinterpret_cast<void*>(game()));
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
bool prepareRewind(unsigned slot) {
    if (!enabled || scopes.depth())
        return false;
    const auto room = findRoom(participant(slot));
    if (!room || room->replicaShell)
        return false;
    // The authority owns this initialized room. Select the item's actual
    // source before joining/freeing rooms; never retain a Scope across cleanup.
    room->activate();
    beforeStart();
    return true;
}
void beforeStart(bool preserveItemPixels) {
    replicaCompanions.clear();
    floorSource.reset();
    replicaDeals.reset();
    presentation::items::reset(preserveItemPixels);
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
    pendingRestart = 0;
    pendingDogma.reset();
    resumeLocations.clear();
    if (!enabled || scopes.depth())
        return;
    // Native floor changes and saves own the complete player roster. Reattach
    // dormant actors for that transaction, then park them again on the new
    // floor if their controllers are still offline.
    // A guest may enter a chest while the host is in another room. Restoring
    // dormant actors canonicalizes the viewport; native departure must still
    // use the initiating room, including its chest and arrival animation.
    const auto source = at<Address>(game(), 0x18300);
    actors::forgetRemoved(location, values(roster()));
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
                for (auto entity : followers(player, *room, true))
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
        const auto descriptor =
            reinterpret_cast<Address>(engine<Desc>(j460::entry::engineRoomsDesc)(
                reinterpret_cast<void*>(game()), key.index, key.dimension));
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
    return j460::installRoomRouting(image) &&
           hook(j460::entry::levelSwapRooms, reinterpret_cast<void*>(swapRooms),
                reinterpret_cast<void**>(&originalSwapRooms)) &&
           hook(j460::entry::entityPlayerAddCoins, reinterpret_cast<void*>(addCoins),
                reinterpret_cast<void**>(&originalCoins)) &&
           hook(j460::entry::playerManagerFindCollectible, reinterpret_cast<void*>(findCollectible),
                reinterpret_cast<void**>(&originalFindCollectible)) &&
           hook(j460::entry::playerManagerCollectibleCount,
                reinterpret_cast<void*>(collectibleCount),
                reinterpret_cast<void**>(&originalCollectibleCount)) &&
           hook(j460::entry::playerManagerFindPlayerType, reinterpret_cast<void*>(findPlayerType),
                reinterpret_cast<void**>(&originalFindPlayerType)) &&
           hook(j460::entry::itemPoolGetCardEx, reinterpret_cast<void*>(getCardEx),
                reinterpret_cast<void**>(&originalGetCardEx)) &&
           hook(j460::entry::roomConfigRandomRoom, reinterpret_cast<void*>(randomRoom),
                reinterpret_cast<void**>(&originalRandomRoom)) &&
           hook(j460::entry::roomGetDevilRoomChance, reinterpret_cast<void*>(dealTotal),
                reinterpret_cast<void**>(&originalDealTotal)) &&
           hook(j460::entry::dealAngelShare, reinterpret_cast<void*>(isaac_lan_angel_share_thunk),
                &originalAngelShare) &&
           hook(j460::entry::levelInitializeDevilAngelRoom,
                reinterpret_cast<void*>(initializeDeals),
                reinterpret_cast<void**>(&originalInitializeDeals)) &&
           hook(j460::entry::roomTrySpawnDevilRoomDoor, reinterpret_cast<void*>(spawnDeals),
                reinterpret_cast<void**>(&originalSpawnDeals)) &&
           hook(j460::entry::playerManagerReplacePlayer, reinterpret_cast<void*>(replacePlayer),
                reinterpret_cast<void**>(&originalReplacePlayer)) &&
           hook(j460::entry::playerTriggerRoomClear, reinterpret_cast<void*>(playerRoomClear),
                reinterpret_cast<void**>(&originalPlayerRoomClear)) &&
           hook(j460::entry::entityPlayerSyncResources, reinterpret_cast<void*>(syncResources),
                reinterpret_cast<void**>(&originalResources)) &&
           hook(j460::entry::gameEnd, reinterpret_cast<void*>(endGame),
                reinterpret_cast<void**>(&originalEnd)) &&
           hook(j460::entry::engineRoomsSave, reinterpret_cast<void*>(save),
                reinterpret_cast<void**>(&originalSave)) &&
           hook(j460::entry::engineRoomsChange, reinterpret_cast<void*>(change),
                reinterpret_cast<void**>(&originalChange)) &&
           hook(j460::entry::roomTransitionUpdate, reinterpret_cast<void*>(nativeRoomChange),
                reinterpret_cast<void**>(&originalNativeRoomChange)) &&
           hook(j460::entry::engineRoomsTransition, reinterpret_cast<void*>(transition),
                reinterpret_cast<void**>(&originalTransition)) &&
           hook(j460::entry::engineRoomsStageTransition, reinterpret_cast<void*>(stageTransition),
                reinterpret_cast<void**>(&originalStage)) &&
           hook(j460::entry::levelSetNextStage, reinterpret_cast<void*>(nextStage),
                reinterpret_cast<void**>(&originalNextStage)) &&
           hook(j460::entry::gameTriggerRKey, reinterpret_cast<void*>(rKey),
                reinterpret_cast<void**>(&originalRKey)) &&
           hook(j460::entry::gameNextVictoryLap, reinterpret_cast<void*>(victoryLap),
                reinterpret_cast<void**>(&originalVictoryLap)) &&
           hook(j460::entry::engineRoomsIsCoop, reinterpret_cast<void*>(isCoop),
                reinterpret_cast<void**>(&originalIsCoop)) &&
           hook(j460::entry::engineRoomsLiving, reinterpret_cast<void*>(living),
                reinterpret_cast<void**>(&originalLiving)) &&
           hook(j460::entry::engineRoomsDead, reinterpret_cast<void*>(dead),
                reinterpret_cast<void**>(&originalDead)) &&
           hook(j460::entry::playerManagerReviveCoop, reinterpret_cast<void*>(reviveAll),
                reinterpret_cast<void**>(&originalReviveAll)) &&
           hook(j460::entry::engineRoomsAward, reinterpret_cast<void*>(award),
                reinterpret_cast<void**>(&originalAward)) &&
           hook(j460::entry::engineRoomsExitGame, reinterpret_cast<void*>(exitGame),
                reinterpret_cast<void**>(&originalExit)) &&
           hook(j460::entry::engineRoomsLeaveRoom, reinterpret_cast<void*>(leaveRoom),
                reinterpret_cast<void**>(&originalLeave)) &&
           hook(j460::entry::cameraSmooth, reinterpret_cast<void*>(cameraSmooth),
                reinterpret_cast<void**>(&originalCameraSmooth)) &&
           hook(j460::entry::cameraDrag, reinterpret_cast<void*>(cameraDrag),
                reinterpret_cast<void**>(&originalCameraDrag)) &&
           hook(j460::entry::playerManagerGetCenter, reinterpret_cast<void*>(playersCenter),
                reinterpret_cast<void**>(&originalPlayersCenter)) &&
           hook(j460::entry::doorUpdate, reinterpret_cast<void*>(doorUpdate),
                reinterpret_cast<void**>(&originalDoorUpdate)) &&
           hook(j460::entry::gridEntityTrapdoorUpdate, reinterpret_cast<void*>(trapdoorUpdate),
                reinterpret_cast<void**>(&originalTrapdoorUpdate)) &&
           hook(j460::entry::nPCNeedlePrepareVisual, reinterpret_cast<void*>(needleVisual),
                reinterpret_cast<void**>(&originalNeedleVisual)) &&
           hook(j460::entry::engineRoomsPostUpdate, reinterpret_cast<void*>(postUpdate),
                reinterpret_cast<void**>(&originalPostUpdate)) &&
           hook(j460::entry::luaPostNewRoom, reinterpret_cast<void*>(postNewRoom),
                reinterpret_cast<void**>(&originalPostNewRoom));
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::pushClosure,  isaac::lua::Symbol::setField,
                           isaac::lua::Symbol::pushBoolean,  isaac::lua::Symbol::pushInteger,
                           isaac::lua::Symbol::pushNumber,   isaac::lua::Symbol::checkNumber,
                           isaac::lua::Symbol::createTable,  isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::checkString,  isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::getTop,       isaac::lua::Symbol::toUserdata,
                           isaac::lua::Symbol::newUserdata,  isaac::lua::Symbol::rawLength,
                           isaac::lua::Symbol::getMetatable, isaac::lua::Symbol::setMetatable,
                           isaac::lua::Symbol::rawSetI,      isaac::lua::Symbol::pushValue,
                           isaac::lua::Symbol::pcall,        isaac::lua::Symbol::error}))
        return false;
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
    function("deal_chances", dealChances);
    function("deal_chances_reset", resetDealChances);
    function("pickup_price", pickupPrice);
    function("pill_state", pillState);
    function("rooms_move", request);
    function("rooms_teleport", teleportToRoom);
    function("rooms_with_player", withPlayer);
    function("rooms_positions", positions);
    function("r_key_begin", beginRKey);
    function("victory_lap_begin", beginVictoryLap);
    function("rooms_chest_ending", chestEnding);
    function("rooms_ready", ready);
    function("rooms_heads", heads);
    function("rooms_sync", syncLocations);
    function("state_clock", stateClock);
    function("room_layout", roomLayout);
    function("room_water_current", roomWaterCurrent);
    function("map_pickups", mapPickups);
    function("map_refresh", refreshMap);
    function("actor_sprites", actorSprites);
    function("actor_pockets", actorPockets);
    function("actor_crafting_bag", actorCraftingBag);
    function("actor_form", actorForm);
    function("actor_companions", actorCompanions);
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

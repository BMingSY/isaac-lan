#include "engine/versions/common/room_hooks.h"
#include "engine/versions/common/room_queries.h"
#include "engine/versions/common/actor_state.h"
#include "engine/versions/common/room_data.h"
#include "engine/item_effects.h"
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "engine/generated_challenge.h"
#include "engine/pause_menu.h"
#include "engine/visuals.h"
#include "engine/audio.h"
#include "engine/combat_feedback.h"
#include "engine/input.h"
#include "engine/rewind.h"
#include "engine/presentation.h"
#include "engine/player_outlines.h"
#include "engine/player_opacity.h"
#include "engine/item_presentation.h"
#include "engine/pickup_preview.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include "engine/versions/common/laser_state.h"
#include "runtime/room_map.h"
#include "compat/bosses/encounters.h"
#include "compat/bosses/rotgut.h"
#include "compat/enemies/room_transitions.h"
#include "compat/routes/mines.h"
#include "compat/routes/mirror.h"
#include "compat/routes/curses.h"
#include "compat/routes/home.h"
#include "compat/items/deal_chances.h"
#include "compat/items/death_certificate.h"
#include "compat/items/room_transitions.h"
#include "runtime/room_clock.h"
#include "compat/items/team_effects.h"
#include "compat/characters/traits.h"
#include "compat/characters/ghost.h"
#include "compat/characters/keeper.h"
#include "compat/characters/team_effects.h"
#include "runtime/actor_roster.h"
#include "runtime/room_scope.h"
#include "presentation/ambient_effects.h"
#include <MinHook.h>
#include <algorithm>
#include <array>
#include <string_view>
#include <cstring>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <vector>
#include <bit>
#include <cmath>
#include <limits>

#include "engine/versions/common/floor_source.h"
#include "engine/versions/common/room_routing.h"
#include "engine/versions/common/room_roster.h"
#include "engine/versions/common/rooms_bindings.h"
#include "engine/versions/common/forgotten_form.h"

namespace isaac::rooms {
namespace {
using Address = std::uintptr_t;
using engine::native_rooms::bindings;
const auto& layout = bindings.layout;
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
    return at<Address>(image, bindings.globalGame);
}
using Allocate = void*(__cdecl*)(std::size_t);
using Delete = void(__cdecl*)(void*, std::size_t);
void* allocate(std::size_t size) {
    return engine<Allocate>(bindings.entry.engineRoomsAllocate)(size);
}
void release(Address p, std::size_t size) {
    if (p)
        engine<Delete>(bindings.entry.engineRoomsDelete)(reinterpret_cast<void*>(p), size);
}
struct Vector {
    Address begin = 0, end = 0, capacity = 0;
};
static_assert(sizeof(Vector) == 12);
Vector& roster() {
    return at<Vector>(game(), layout.game.players);
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
const auto& contextOffsets = bindings.contextOffsets;
std::uint32_t readContext(unsigned field) {
    const auto offset = contextOffsets[field];
    return offset ? at<std::uint32_t>(game(), *offset) : 0;
}
void writeContext(unsigned field, std::uint32_t value) {
    if (const auto offset = contextOffsets[field])
        at<std::uint32_t>(game(), *offset) = value;
}
int controlRestoreState() {
    // J835 has no J511 game-state gate: its native arrival always releases
    // controls and Game::End does not test that newer state machine.
    const auto offset = layout.game.controlRestoreGuard;
    return offset ? at<int>(game(), *offset) : 0;
}
struct AmbushState {
    Vector pendingWaves;
    std::array<std::uint32_t, 13> scalars{};
};
static_assert(sizeof(AmbushState) == 0x40);
struct Room;
Room* sharedOwner = nullptr;
void selectSharedState(Room* room);
// Native room-sized postprocess buffers are process globals. Their native
// shared-pointer pairs must move with the room, including reference owners.
// Keeping only fx_ray isolated lets a 2x2 room overwrite a 1x1 room's surfaces.
const auto& renderImages = bindings.renderImages;
struct Room {
    RoomClock clock;
    Key key;
    Address pointer;
    bool owned;
    std::array<std::uint32_t, engine::native_rooms::contextFieldCount> context{};
    Vector scratch;
    AmbushState ambush;
    std::array<std::array<Address, 2>, engine::native_rooms::renderImageCount> images{};
    // A guest retains remote actors for the vanilla multiplayer HUD, without
    // loading their rooms, running their entry logic, or allocating backdrops.
    bool replicaShell = false;
    bool graphicsRefresh = true;
    unsigned char sceneSnapshot = 0;
    unsigned updates = 0, halves = 0;
    Room() {
        // The leading Ambush vector is immutable XML configuration. Each room
        // owns only its shuffled pending-wave vector, counters and RNGs.
        ambush.scalars = at<AmbushState>(game(), layout.game.ambushPending).scalars;
        ambush.scalars[2] = ambush.scalars[3] = ambush.scalars[4] = 0;
    }
    void capture() {
        for (unsigned i = 0; i < context.size(); ++i)
            context[i] = readContext(i);
        graphicsRefresh = at<bool>(game(), layout.game.graphicsRefresh);
        sceneSnapshot = at<unsigned char>(game(), layout.game.sceneSnapshot);
    }
    void activate() {
        selectSharedState(this);
        at<Address>(game(), layout.game.room) = pointer;
        for (unsigned i = 0; i < context.size(); ++i)
            writeContext(i, context[i]);
        at<bool>(game(), layout.game.graphicsRefresh) = graphicsRefresh;
        at<unsigned char>(game(), layout.game.sceneSnapshot) = sceneSnapshot;
    }
};
void selectSharedState(Room* room) {
    if (room == sharedOwner)
        return;
    auto& engineState = at<AmbushState>(game(), layout.game.ambushPending);
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
    const auto controller = at<int>(player, layout.player.controller);
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
        if (at<unsigned>(player, layout.entity.variant) != 0 ||
            at<Address>(player, layout.entity.parent))
            continue;
        const auto twin = at<Address>(player, layout.player.twin);
        if (twin && at<int>(player, layout.player.index) > at<int>(twin, layout.player.index))
            continue;
        const int controller = at<int>(player, layout.player.controller);
        if (useControllers && controller >= 1 && controller <= 4 &&
            std::any_of(result.begin(), result.end(), [controller](Address p) {
                return at<int>(p, layout.player.controller) == controller;
            }))
            continue;
        result.push_back(player);
    }
    if (useControllers && std::all_of(result.begin(), result.end(), [](Address p) {
            return at<int>(p, layout.player.controller) >= 1 &&
                   at<int>(p, layout.player.controller) <= 4;
        }))
        std::sort(result.begin(), result.end(), [](Address a, Address b) {
            return at<int>(a, layout.player.controller) < at<int>(b, layout.player.controller);
        });
    return result;
}
std::vector<Address> controlledActors(Address head) {
    std::vector<Address> result;
    const int controller = at<int>(head, layout.player.controller);
    for (auto player : values(roster()))
        if (player == head ||
            (controller >= 1 && controller <= 4 &&
             at<int>(player, layout.player.controller) == controller) ||
            at<Address>(head, layout.player.twin) == player ||
            at<Address>(player, layout.player.twin) == head)
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
std::set<unsigned> pendingArrivalRecovery;
// The same occupied room can have a different previous room for each seat.
std::array<std::optional<Key>, lan::maxPlayers> previousSeatRoom;
struct StageRequest {
    bool same;
    int animation;
    Address player;
    int sourceRoom;
    int sourceDimension = 0;
};
std::optional<StageRequest> pendingStage;
engine::native_rooms::FloorSource floorSource{layout.roomDescriptor.minimumRoom};
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
    floorSource.select(at<int>(reinterpret_cast<Address>(level), layout.game.roomIndex),
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
    std::array<std::uint32_t, engine::native_rooms::contextFieldCount> previous;
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
        : room(&target), previousShared(sharedOwner),
          previousRoom(at<Address>(game(), layout.game.room)), previousRoster(roster()),
          reconcilePlayers(reconcile), originalPlayers(players) {
        for (auto player : players)
            originalControllers[player] = at<int>(player, layout.player.controller);
        for (unsigned i = 0; i < previous.size(); ++i)
            previous[i] = readContext(i);
        previousRefresh = at<bool>(game(), layout.game.graphicsRefresh);
        previousSnapshot = at<unsigned char>(game(), layout.game.sceneSnapshot);
        // A display callback can scope the same room again. Its temporary
        // roster must not overwrite an outer scope's live allocation.
        storage = scopes.depth() ? &nestedScratch : &room->scratch;
        assign(*storage, players);
        roster() = *storage;
        room->activate();
        binding.emplace(scopes, *room, previousRoster, &roster());
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
            auto all = actors::reconcile(values(roster()), originalPlayers, current,
                                         [&](Address old, Address candidate) {
                                             return originalControllers.at(old) ==
                                                    at<int>(candidate, layout.player.controller);
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
                    logger("actor_replaced index=" + std::to_string(i) + " type=" +
                           std::to_string(at<int>(all[i], layout.player.type)) + " controller=" +
                           std::to_string(at<int>(all[i], layout.player.controller)) +
                           " parent=" + std::to_string(at<Address>(all[i], layout.entity.parent)) +
                           " twin=" + std::to_string(at<Address>(all[i], layout.player.twin)));
            if (scopes.depth() == 1)
                participants = logicalPlayers();
        }
        at<Address>(game(), layout.game.room) = previousRoom;
        for (unsigned i = 0; i < previous.size(); ++i)
            writeContext(i, previous[i]);
        at<bool>(game(), layout.game.graphicsRefresh) = previousRefresh;
        at<unsigned char>(game(), layout.game.sceneSnapshot) = previousSnapshot;
        binding->restoreParent();
        selectSharedState(previousShared);
        if (storage == &nestedScratch)
            release(nestedScratch.begin, nestedScratch.capacity - nestedScratch.begin);
        binding.reset();
    }
};
struct TeamScope : engine::native_rooms::TeamRoster<decltype(scopes), Vector> {
    TeamScope() : TeamRoster(scopes, roster(), enabled) {}
};
using FindCollectible = void*(__attribute__((thiscall)) *)(void*, int, void*, bool);
using CollectibleCount = int(__attribute__((thiscall)) *)(void*, int);
FindCollectible originalFindCollectible;
CollectibleCount originalCollectibleCount;
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
void withTypeQuery(int kind, Address caller, const std::function<void()>& query) {
    // Share only the native shop and random collectible checks. Personal
    // character checks, including Devil buyers, keep their room/actor scope.
    using compat::characters::TeamEffect;
    const bool keeper = compat::characters::sharedCharacterEffect(kind, TeamEffect::shop) &&
                        (caller == bindings.entry.keeperShopQueryReturn ||
                         caller == bindings.entry.keeperPriceQueryReturn);
    const bool lost =
        compat::characters::sharedCharacterEffect(kind, TeamEffect::randomCollectibles) &&
        caller == bindings.entry.itemPoolTaintedLostReturn;
    if (!keeper && !lost) {
        query();
        return;
    }
    TeamScope team;
    query();
}
using GetCardEx = int(__stdcall*)(unsigned, unsigned, unsigned, unsigned, bool);
GetCardEx originalGetCardEx;
int __stdcall getCardEx(unsigned seed, unsigned special, unsigned rune, unsigned suit,
                        bool nonCards) {
    // J511 inlines its Tainted Lost lookup here rather than FindPlayerType.
    // Temporarily expose the team only when that shared trait is present.
    bool shared = false;
    {
        TeamScope team;
        shared = compat::characters::sharedCharacterEffect(
                     compat::ids::player::lostB, compat::characters::TeamEffect::randomCards) &&
                 engine::native_room_queries::hasType(
                     reinterpret_cast<void*>(game() + layout.game.playerManager),
                     compat::ids::player::lostB);
    }
    if (!shared)
        return originalGetCardEx(seed, special, rune, suit, nonCards);
    TeamScope team;
    return originalGetCardEx(seed, special, rune, suit, nonCards);
}
using RandomRoom = void*(__attribute__((thiscall)) *)(void*, unsigned, bool, int, int, int, int,
                                                      int, int, int, void*, int, int);
RandomRoom originalRandomRoom;
void* templateConfig = nullptr;
Address templateGame = 0;
void* __attribute__((fastcall)) randomRoom(void* config, void*, unsigned seed, bool reduce,
                                           int stage, int type, int shape, int minimum, int maximum,
                                           int difficultyLow, int difficultyHigh, void* doors,
                                           int subtype, int mode) {
    templateConfig = config;
    templateGame = game();
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    if (type == 2 && caller == bindings.entry.keeperRandomRoomReturn) {
        bool keeper = runtime::startingPartyHasCharacter(compat::ids::player::keeperB);
        if (enabled) {
            TeamScope team;
            keeper = engine::native_room_queries::hasType(
                reinterpret_cast<void*>(game() + layout.game.playerManager),
                compat::ids::player::keeperB);
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
// The internal J511 conditional Angel query returns in XMM0, unlike public
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
    Address previousRoom = at<Address>(game(), layout.game.room);
    int previousIndex = at<int>(game(), layout.game.roomIndex);
    int previousDimension = at<int>(game(), layout.game.dimension);
    DealRoomScope() {
        if (!enabled)
            return;
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        for (const auto& [key, room] : loaded) {
            if (room->replicaShell)
                continue;
            const auto descriptor =
                reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
                    reinterpret_cast<void*>(game()), key.index, key.dimension));
            if (descriptor && at<int>(descriptor, layout.roomDescriptor.listIndex) ==
                                  at<int>(game(), layout.game.lastBossRoomListIndex)) {
                at<Address>(game(), layout.game.room) = room->pointer;
                at<int>(game(), layout.game.roomIndex) = key.index;
                at<int>(game(), layout.game.dimension) = key.dimension;
                break;
            }
        }
    }
    ~DealRoomScope() {
        at<Address>(game(), layout.game.room) = previousRoom;
        at<int>(game(), layout.game.roomIndex) = previousIndex;
        at<int>(game(), layout.game.dimension) = previousDimension;
    }
};
float __attribute__((fastcall)) dealTotal(void* room, void*) {
    if (enabled && runtime::replica() && replicaDeals)
        return replicaDeals->total;
    TeamScope team;
    if (!enabled)
        return originalDealTotal(room);
    DealRoomScope context;
    auto total = originalDealTotal(reinterpret_cast<void*>(at<Address>(game(), layout.game.room)));
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
    const auto owner = at<int>(reinterpret_cast<Address>(player), layout.player.controller) - 1;
    const auto dimension = at<int>(game(), layout.game.dimension);
    const auto index = at<int>(game(), layout.game.roomIndex);
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
    if (!enabled || !scopes.teamRoster() || !at<bool>(next, layout.entity.registered))
        return originalReplacePlayer(manager, oldPlayer, nextPlayer);
    const auto scoped = values(roster());
    const auto oldIndex = at<unsigned>(old, layout.player.index),
               nextIndex = at<unsigned>(next, layout.player.index);
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
    const auto actor = reinterpret_cast<Address>(player);
    if (!location.contains(actor)) {
        // Native constructors broadcast their zero-initialized resource fields
        // before Scope enrolls the new body. Inherit the live team pool first.
        for (const auto owner : participants)
            if (owner != actor && location.contains(owner)) {
                engine<CopyResources>(bindings.entry.entityPlayerCopyResourcesTo)(
                    reinterpret_cast<void*>(owner), player, shared);
                break;
            }
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
            engine<CopyResources>(bindings.entry.entityPlayerCopyResourcesTo)(
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
    // The native center query caches this globally by render frame, not by room/roster. A second
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
        const auto target = at<Address>(room->pointer, layout.room.camera);
        originalCameraSmooth(reinterpret_cast<void*>(target), halfFrame);
        // Mirror Manager's one-frame focus override reset for every room.
        at<bool>(target, layout.camera.focusOverride) = false;
    }
}
void __attribute__((fastcall)) cameraDrag(void* camera, void*) {
    if (!enabled || scopes.depth() || transferring) {
        originalCameraDrag(camera);
        return;
    }
    if (runtime::replica())
        return;
    const auto manager = *reinterpret_cast<Address*>(image + bindings.globalManager);
    const bool halfFrame = (at<unsigned>(manager, layout.manager.renderFrame) & 1u) != 0;
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
        const auto target = at<Address>(room->pointer, layout.room.camera);
        originalCameraDrag(reinterpret_cast<void*>(target));
        if (halfFrame)
            at<bool>(target, layout.camera.focusOverride) = false;
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
    engine::GeneratedChallengeRewardScope scope;
    if (!runtime::allowChallengeEvent("shared_award")) {
        originalAward(room);
        return;
    }
    // Loot quantity and shared loot-affecting items use the original complete
    // co-op roster; combat targeting continues to use only room occupants.
    TeamScope team;
    originalAward(room);
}
RoomCall originalReviveAll;
void __attribute__((fastcall)) reviveAll(void* manager, void*) {
    if (runtime::replica() || !runtime::allowChallengeEvent("coop_revive"))
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
    if (ending == static_cast<int>(lan::ending::gameOver) &&
        !runtime::allowChallengeEvent("game_over"))
        return;
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
    const auto state = controlRestoreState();
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
    const Address list = room + (layout.room.entities + layout.entityList.renderArray);
    const auto data = at<Address>(list, layout.entityList.data);
    for (unsigned i = 0; i < at<unsigned>(list, layout.entityList.count); ++i) {
        const auto entity = at<Address>(data, i * 4);
        if (at<bool>(entity, layout.entity.interpolated)) {
            at<float>(entity, layout.entity.positionX) = at<float>(entity, layout.entity.previousX);
            at<float>(entity, layout.entity.positionY) = at<float>(entity, layout.entity.previousY);
            at<bool>(entity, layout.entity.interpolated) = false;
        }
    }
}
void moveEntity(Address entity, Room& from, Room& to) {
    const auto& listLayout = layout.entityList;
    bool persistent = false;
    for (auto offset = listLayout.firstArray; offset <= listLayout.lastArray;
         offset += listLayout.arrayStride) {
        const auto list = from.pointer + layout.room.entities + offset;
        auto data = reinterpret_cast<Address*>(at<Address>(list, listLayout.data));
        auto& size = at<unsigned>(list, listLayout.count);
        for (unsigned i = 0; i < size;) {
            if (data[i] != entity) {
                ++i;
                continue;
            }
            persistent |= offset == listLayout.persistentArray;
            std::memmove(data + i, data + i + 1, (--size - i) * sizeof(Address));
        }
    }
    using Invalidate = void(__attribute__((thiscall))*)(void*, unsigned, unsigned, unsigned);
    engine<Invalidate>(bindings.entry.engineRoomsInvalidate)(
        reinterpret_cast<void*>(from.pointer + layout.room.entities),
        at<unsigned>(entity, layout.entity.type), at<unsigned>(entity, layout.entity.variant),
        at<unsigned>(entity, layout.entity.subtype));
    at<bool>(entity, layout.entity.registered) = false;
    at<unsigned>(entity, layout.entity.index) =
        at<unsigned>(to.pointer, layout.room.nextEntityIndex)++;
    using Add = void(__attribute__((thiscall))*)(void*, void*);
    engine<Add>(bindings.entry.engineRoomsAdd)(
        reinterpret_cast<void*>(to.pointer + layout.room.entities),
        reinterpret_cast<void*>(entity));
    // Add rebuilds the ordinary type lists, but dynamic native persistence is
    // separate. Preserve that membership before Room::Init can discard an NPC
    // or a familiar's room-entry callback searches for its persistent body.
    if (persistent) {
        const auto list = to.pointer + layout.room.entities + listLayout.persistentArray;
        const auto data = reinterpret_cast<const Address*>(at<Address>(list, listLayout.data));
        const std::span<const Address> members(data, at<unsigned>(list, listLayout.count));
        if (std::find(members.begin(), members.end(), entity) == members.end())
            engine<Add>(bindings.entry.engineRoomsAddPersistent)(
                reinterpret_cast<void*>(to.pointer + layout.room.entities),
                reinterpret_cast<void*>(entity));
    }
}
std::vector<Address> followers(Address player, const Room& room, bool departingFloor = false) {
    std::vector<Address> candidates, result;
    // Native lists keep attached knives in the persistence list along with familiars;
    // transient weapons can also occur in the ordinary/effect lists. Dark Esau
    // is an NPC in the enemy list, despite following a player across rooms.
    // Preserve native iteration order and avoid transferring an entity twice.
    for (unsigned offset : {layout.entityList.persistentArray, layout.entityList.firstArray,
                            layout.entityList.renderArray, layout.entityList.enemyArray}) {
        const auto list = room.pointer + layout.room.entities + offset;
        for (unsigned i = 0; i < at<unsigned>(list, layout.entityList.count); ++i) {
            const auto entity = at<Address>(at<Address>(list, layout.entityList.data), i * 4);
            if (std::find(candidates.begin(), candidates.end(), entity) == candidates.end())
                candidates.push_back(entity);
        }
    }
    auto owned = [player](Address entity) {
        for (unsigned ancestor = 0; entity && ancestor < 8; ++ancestor) {
            if (entity == player)
                return true;
            if (at<unsigned>(entity, layout.entity.type) == 3)
                return at<Address>(entity, layout.familiar.player) == player;
            entity = at<Address>(entity, layout.entity.parent);
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
        if (compat::characters::taintedJacob(at<int>(occupant, layout.player.type)))
            jacobs.push_back(occupant);
    for (auto entity : candidates) {
        const auto type = at<unsigned>(entity, layout.entity.type);
        const auto parent = at<Address>(entity, layout.entity.parent);
        const bool tear = type == compat::ids::entity::tear;
        const auto attachment =
            tear && !parent ? at<Address>(entity, layout.entity.spawner) : parent;
        bool darkEsau = type == compat::characters::darkEsau &&
                        (at<Address>(player, layout.player.darkEsau) == entity ||
                         owned(at<Address>(entity, layout.entity.parent)) ||
                         owned(at<Address>(entity, layout.entity.spawner)) ||
                         owned(at<Address>(entity, layout.entity.child)));
        // Native room saves restore Dark Esau as an NPC without a spawner and
        // cannot restore a player's EntityPtr across our independent rooms.
        // Rebind only when the room has one unambiguous Tainted Jacob owner.
        if (type == compat::characters::darkEsau && !darkEsau && jacobs.size() == 1 &&
            jacobs[0] == player && !at<Address>(entity, layout.entity.parent) &&
            !at<Address>(entity, layout.entity.spawner) &&
            !at<Address>(entity, layout.entity.child)) {
            using SetRef = void(__attribute__((fastcall))*)(void*, void*);
            engine<SetRef>(bindings.entry.entityPtrAssign)(
                reinterpret_cast<void*>(player + layout.player.darkEsau),
                reinterpret_cast<void*>(entity));
            engine<SetRef>(bindings.entry.entityPtrAssign)(
                reinterpret_cast<void*>(entity + layout.entity.spawner),
                reinterpret_cast<void*>(player));
            darkEsau = true;
        }
        if ((type == 3 && at<Address>(entity, layout.familiar.player) == player) ||
            (type == 8 && (owned(at<Address>(entity, layout.entity.parent)) ||
                           owned(at<Address>(entity, layout.entity.spawner)))) ||
            compat::items::roomFollower(
                type, at<unsigned>(entity, layout.entity.variant), owned(attachment),
                at<unsigned>(entity, layout.entity.subtype),
                tear ? at<std::uint64_t>(entity, layout.tear.flagsHigh) : 0) ||
            darkEsau ||
            (departingFloor &&
             compat::items::floorFollower(type, at<unsigned>(entity, layout.entity.variant),
                                          at<Address>(player, layout.player.redemptionEffect) ==
                                              entity)) ||
            compat::routes::escapeFollower(
                type, room.key.dimension,
                (at<unsigned>(game(), layout.game.levelFlags) & (1u << 22)) != 0, lastOccupant))
            result.push_back(entity);
    }
    return result;
}
void place(Address entity, Vec2 position) {
    at<Vec2>(entity, layout.entity.positionX) = at<Vec2>(entity, layout.entity.previousX) =
        position;
    at<Vec2>(entity, layout.entity.velocity) = {0, 0};
    at<bool>(entity, layout.entity.interpolated) = false;
}
void clearRoomTransitionTarget(Address player) {
    // Native full room entry clears the attraction used by holes/chests.
    // Joining a resident room bypasses that entry, so its departing target
    // must not keep pulling the arriving actor back during normal movement.
    at<Vec2>(player, layout.player.roomTransitionTarget) = {0, 0};
}
bool occupiedCombat(const Room& room, Address arriving) {
    if (room.replicaShell)
        return false;
    using IsClear = bool(__attribute__((thiscall))*)(void*);
    // Native Room::IsClear reads its descriptor's CLEAR flag. Reuse the same
    // native predicate used by Lua, not an enemy-count approximation.
    if (engine<IsClear>(bindings.entry.roomIsClear)(reinterpret_cast<void*>(room.pointer)))
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
        engine<DoorPosition>(bindings.entry.engineRoomsDoorPosition)(
            reinterpret_cast<void*>(room.pointer), &position, door);
        constexpr Vec2 inward[] = {{40, 0}, {0, 40}, {-40, 0}, {0, -40}};
        position.x += inward[door % 4].x;
        position.y += inward[door % 4].y;
        landing = position;
    }
    if (landing) {
        place(player, *landing);
        for (auto entity : companions)
            if (at<unsigned>(entity, layout.entity.type) != compat::ids::entity::mothersShadow &&
                !compat::characters::taintedJacobPursuer(
                    at<unsigned>(entity, layout.entity.type),
                    at<unsigned>(entity, layout.entity.variant)))
                place(entity, *landing);
    }
    if (protect) {
        using Cooldown = void(__attribute__((thiscall))*)(void*, int);
        engine<Cooldown>(bindings.entry.engineRoomsCooldown)(reinterpret_cast<void*>(player), 90);
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
    if (enabled && !runtime::replica() && caller == bindings.entry.levelMazeSwapReturn) {
        const int dimension = at<int>(game(), layout.game.dimension);
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
            engine<UpdateSprite>(bindings.entry.spriteUpdate)(
                static_cast<char*>(player) + layout.player.chargeSprites + i * layout.sprite.size);
        // Original emote animation, dice result and expiry are local presentation too.
        if (bindings.entry.emoteUpdate)
            engine<UpdateSprite>(bindings.entry.emoteUpdate)(static_cast<char*>(player) +
                                                             layout.player.emote);
        return;
    }
    const auto before = actor;
    actor = reinterpret_cast<Address>(player);
    const auto slot = slotOf(actor, 4);
    const bool personalMap = enabled && slot < 4 && runtime::challengeActive();
    if (personalMap)
        runtime::mapView(true, slot, true);
    presentation::items::withActor(player, [&] { originalPlayerUpdate(player); });
    if (personalMap)
        runtime::mapView(false, slot, true);
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
        const auto desc = reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
            reinterpret_cast<void*>(game()), index,
            dimension < 0 ? source.key.dimension : dimension));
        if (!desc || !at<Address>(desc, layout.roomDescriptor.data))
            return std::nullopt;
        const auto key =
            canonicalRoomDestination(index, at<int>(desc, layout.roomDescriptor.safeGridIndex),
                                     at<int>(desc, layout.roomDescriptor.dimension));
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
    return runtime::requestRoom({static_cast<std::uint8_t>(at<int>(game(), layout.game.stage)),
                                 static_cast<std::uint8_t>(at<int>(game(), layout.game.stageType)),
                                 static_cast<std::uint8_t>(source.dimension),
                                 static_cast<std::uint8_t>(target->dimension),
                                 static_cast<std::int16_t>(source.index),
                                 static_cast<std::int16_t>(target->index), teleport});
}
std::array<int, engine::native_rooms::doorCount> entranceNeighbors(const Key& key) {
    const auto& descriptor = layout.roomDescriptor;
    using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
    std::array<int, engine::native_rooms::doorCount> neighbors;
    neighbors.fill(-1);
    const auto target = reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
        reinterpret_cast<void*>(game()), key.index, key.dimension));
    if (!target || !at<Address>(target, descriptor.data))
        return neighbors;
    for (unsigned slot = 0; slot < neighbors.size(); ++slot) {
        const int index = at<int>(target, descriptor.doors + slot * sizeof(int));
        if (index < 0 || index >= 169)
            continue;
        const auto neighbor = reinterpret_cast<Address>(engine<Desc>(
            bindings.entry.engineRoomsDesc)(reinterpret_cast<void*>(game()), index, key.dimension));
        if (neighbor && at<Address>(neighbor, descriptor.data))
            neighbors[slot] = at<int>(neighbor, descriptor.safeGridIndex);
    }
    return neighbors;
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
        const int resolved =
            resolveEntranceDoor(door, it->second->key.index, entranceNeighbors(key));
        if (resolved != door)
            logger("room_entry_resolved slot=" + std::to_string(slotOf(player)) + " from=" +
                   std::to_string(it->second->key.index) + " to=" + std::to_string(key.index) +
                   " hint=" + std::to_string(door) + " entry=" + std::to_string(resolved));
        door = resolved;
    }
    pending.push_back({player, key, door, teleport, animateDeparture, animation, landing, routing});
    if (teleport && animateDeparture) {
        using Animate = void(__attribute__((thiscall))*)(void*, bool);
        for (auto p : controlledActors(player))
            engine<Animate>(bindings.entry.playerAnimateTeleport)(reinterpret_cast<void*>(p), true);
    }
    return true;
}
void transitionRequest(void* g, int index, int direction, int animation, void* player,
                       int dimension, Address caller, const std::function<void()>& original) {
    if (!enabled || transferring) {
        original();
        return;
    }
    const auto manager = at<Address>(image, bindings.globalManager);
    if (!runtime::replica() && index == -10 && direction == -1 && animation == 1 && !player &&
        dimension == -1 && at<int>(game(), layout.game.stage) == 13 &&
        at<int>(game(), layout.game.stageType) == 1 &&
        at<bool>(manager, layout.manager.cinematicActive) &&
        at<int>(manager, layout.manager.cinematicId) == 25) {
        pendingDogma = at<Address>(game(), layout.game.room);
        return;
    }
    const auto who = currentActor(player);
    if (!runtime::replica() && !player && scopes.current() &&
        caller == bindings.entry.momsHandTransitionCall + 5 &&
        compat::enemies::capturedRoomReturn(index, at<int>(game(), layout.game.startingRoom),
                                            direction, animation, dimension)) {
        // The grabbing NPC requests a room-wide fade without a player argument.
        // Its native update already cleared the captured flags; complete the
        // transfer and visibility for this room's party, including resident
        // destinations. Players in other rooms retain their own state.
        const auto source = scopes.current();
        for (const auto head : participants) {
            const auto found = location.find(head);
            if (found != location.end() && found->second == source &&
                (connectedMask & (1u << slotOf(head)))) {
                if (!queue(head, index, dimension, -1, false, false, animation))
                    runtime::abort("Cannot return the captured room's players");
                pendingArrivalRecovery.insert(slotOf(head));
            }
        }
        return;
    }
    if (!runtime::replica() && !player && scopes.current() &&
        scopes.current()->key.dimension == 0) {
        const auto source = scopes.current();
        const auto list = source->pointer + (layout.room.entities + layout.entityList.renderArray);
        bool transfer = compat::bosses::rotgutReturn(source->key.index, index,
                                                     at<int>(game(), layout.game.specialRoomOrigin),
                                                     direction, animation, dimension);
        for (unsigned i = 0; !transfer && i < at<unsigned>(list, layout.entityList.count); ++i) {
            const auto entity = at<Address>(at<Address>(list, layout.entityList.data), i * 4);
            transfer = compat::bosses::rotgutSwallow(index, direction, animation, dimension,
                                                     at<unsigned>(entity, layout.entity.type),
                                                     at<unsigned>(entity, layout.entity.variant));
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
    if (!runtime::replica() && compat::items::deathCertificateTransfer(
                                   animation, at<int>(game(), layout.game.dimension), dimension)) {
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
        const auto source = at<Address>(game(), layout.game.room);
        if (room && !room->replicaShell && room->pointer == source &&
            compat::routes::hourglassHomeSource(
                at<int>(game(), layout.game.stage), at<int>(game(), layout.game.stageType),
                at<int>(game(), layout.game.difficulty), at<int>(game(), layout.game.roomIndex),
                at<int>(game(), layout.game.startingRoom), at<bool>(source, 1))) {
            // A native first-room Home use can precede every checkpoint. Its
            // stage hook only queues departure, so the current Scope stays
            // valid. Do not let an empty buffer enter ordinary rewind code.
            const bool hadStage = pendingStage.has_value();
            original();
            if (!hadStage && pendingStage &&
                compat::routes::homeTransition(pendingStage->same, pendingStage->animation))
                pendingStage->player = who;
        }
        return;
    }
    // These are the collectible and trinket branches that read Level's last
    // room. Keep native in-place revivals and explicit Mod destinations intact.
    if (!runtime::replica() && who &&
        (caller == bindings.entry.collectibleRevivalRoomCall + 5 ||
         caller == bindings.entry.trinketRevivalRoomCall + 5)) {
        const auto slot = slotOf(who);
        if (const auto previous = previousSeatRoom[slot];
            previous &&
            queue(who, previous->index, previous->dimension, at<int>(game(), layout.game.enterDoor),
                  false, false, animation, std::nullopt, RoomRouting::resolved)) {
            pendingArrivalRecovery.insert(slot);
            return;
        }
    }
    // Native item revivals (Dead Cat, Collar, Ankh, 1up) hide the actor until
    // RoomTransition::ChangeRoom restores visibility. Our per-actor transfer
    // bypasses that process-wide screen, including when the previous room is
    // already the actor's current room.
    if (compat::items::revivalTransition(animation) && who)
        pendingArrivalRecovery.insert(slotOf(who));
    // StartRoomTransition normally initializes the Blue Key encounter before
    // switching rooms. Keep its native descriptor/door rules in this scope.
    if (who &&
        compat::items::blueRoomTransition(animation, at<int>(game(), layout.game.dimension),
                                          dimension) &&
        engine::items::initializeBlueRoom(g, at<int>(game(), layout.game.roomIndex), index,
                                          direction))
        index = compat::items::blueRoomIndex;
    const int leave = at<int>(game(), layout.game.leaveDoor);
    const auto mirrorEntry = compat::routes::mirrorEntrance(animation, leave);
    int enter =
        mirrorEntry.value_or(leave >= 0 && leave < 8 ? (leave % 4 + 2) % 4 + (leave / 4) * 4 : -1);
    if (enter >= 0 && !mirrorEntry) {
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        const auto target = reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
            reinterpret_cast<void*>(game()), index, dimension));
        if (target)
            for (int slot = 0; slot < 8; ++slot) {
                const int neighbor =
                    at<int>(target, layout.roomDescriptor.doors + slot * sizeof(int));
                if (neighbor < 0 || neighbor >= 169 || slot % 4 != (leave % 4 + 2) % 4)
                    continue;
                const auto source =
                    reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
                        reinterpret_cast<void*>(game()), neighbor, dimension));
                if (source && at<int>(source, layout.roomDescriptor.safeGridIndex) ==
                                  at<int>(game(), layout.game.roomIndex)) {
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
bool forwardingUpperTransition = false;
Transition originalRoomTransitionStart = nullptr;
void __attribute__((fastcall)) transition(void* g, void*, int index, int direction, int animation,
                                          void* player, int dimension) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    transitionRequest(g, index, direction, animation, player, dimension, caller, [&] {
        struct Restore {
            bool previous = forwardingUpperTransition;
            ~Restore() {
                forwardingUpperTransition = previous;
            }
        } restore;
        forwardingUpperTransition = true;
        originalTransition(g, index, direction, animation, player, dimension);
    });
}
void __attribute__((fastcall)) startRoomTransition(void* target, void*, int index, int direction,
                                                   int animation, void* player, int dimension) {
    const auto forward = [&] {
        originalRoomTransitionStart(target, index, direction, animation, player, dimension);
    };
    if (forwardingUpperTransition) {
        forward();
        return;
    }
    // J835's Mom's Hand, Dogma and Death Certificate call this lower method
    // directly. Its receiver is RoomTransition, while policy borrows Game.
    // Level::ChangeRoom still owns curse routing for these native requests.
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    transitionRequest(reinterpret_cast<void*>(game()), index, direction, animation, player,
                      dimension, caller, forward);
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
    if (!queue(currentActor(), index, dimension, at<int>(game(), layout.game.enterDoor)))
        logger("room_change=REJECTED actor_unresolved");
}
void __attribute__((fastcall)) stageTransition(void* g, void*, bool same, int animation,
                                               void* player) {
    if (enabled && !runtime::replica() && !runtime::allowChallengeEvent("floor"))
        return;
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
        pendingStage = StageRequest{same, animation, currentActor(player),
                                    at<int>(game(), layout.game.roomIndex),
                                    at<int>(game(), layout.game.dimension)};
}
void __cdecl rKey() {
    if (enabled && !runtime::replica() && !runtime::allowChallengeEvent("floor"))
        return;
    if (!enabled) {
        originalRKey();
        return;
    }
    // J511's R Key timer calls TriggerRKey directly. Defer it until the room
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
    engine<RoomCall>(bindings.entry.ambushDestroyWaveQueue)(&room.ambush.pendingWaves);
    using AssignImage = void*(__attribute__((thiscall))*)(void*, const void*);
    const std::array<Address, 2> emptyImage{};
    for (auto& handle : room.images)
        engine<AssignImage>(bindings.entry.roomAssignLightTexture)(&handle, &emptyImage);
    release(room.scratch.begin, room.scratch.capacity - room.scratch.begin);
    room.scratch = {};
    if (room.owned) {
        engine<RoomCall>(bindings.entry.roomDestruct)(reinterpret_cast<void*>(room.pointer));
        release(room.pointer, layout.room.size);
    }
}
using LuaFn = int(__cdecl*)(lua_State*);
isaac::lua::API lua{};
int dealChances(lua_State* L) {
    if (!lua.getTop(L)) {
        lua.pushNumber(L, engine<DealTotal>(bindings.entry.roomGetDevilRoomChance)(
                              reinterpret_cast<void*>(at<Address>(game(), layout.game.room))));
        // Use the same detours/return ABI as the actual HUD and room generator.
        lua.pushNumber(
            L, queryAngelShare(reinterpret_cast<void*>(image + bindings.entry.dealAngelShare)));
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
    const auto pickup = pickupWrapper[1] - layout.entity.sprite,
               player = playerWrapper[1] - layout.entity.sprite;
    if (at<unsigned>(pickup, layout.entity.type) != 5 ||
        at<unsigned>(player, layout.entity.type) != 1 || !at<bool>(pickup, layout.entity.active) ||
        !at<bool>(player, layout.entity.active)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto room = findRoom(player);
    if (!room || room->replicaShell || at<int>(room->pointer, layout.room.type) != 14) {
        lua.pushBoolean(L, false);
        return 1;
    }
    Scope scope(*room, {player}, false);
    const auto price = bindings.pickupPrice(
        image, room->pointer, at<int>(pickup, layout.entity.variant),
        at<int>(pickup, layout.entity.subtype), at<int>(pickup, layout.pickup.shopItemId));
    lua.pushInteger(L, price);
    return 1;
}
int pillState(lua_State* L) {
    try {
        // The native pool has 15 pill color assignments and identification
        // bytes. Horse-pill colors use the same masked color index.
        const auto pool = game() + layout.game.itemPool;
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
                at<int>(pool, layout.itemPool.pillEffects + i * 4) = effects[i];
                at<unsigned char>(pool, layout.itemPool.pillIdentified + i) = known[i];
            }
            lua.pushBoolean(L, true);
        } else {
            lan::Writer w(lan::Message::world);
            for (unsigned i = 0; i < effects.size(); ++i) {
                w.u32(at<int>(pool, layout.itemPool.pillEffects + i * 4));
                w.u8(at<bool>(pool, layout.itemPool.pillIdentified + i));
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
        auto update = reinterpret_cast<void*>(
            at<Address>(at<Address>(participants.front(), 0), layout.entity.updateMethod));
        if (MH_CreateHook(update, reinterpret_cast<void*>(playerUpdate),
                          reinterpret_cast<void**>(&originalPlayerUpdate)) != MH_OK ||
            MH_EnableHook(update) != MH_OK)
            return false;
    }
    auto room = std::make_unique<Room>();
    room->pointer = at<Address>(game(), layout.game.room);
    room->owned = true;
    room->key = {at<int>(game(), layout.game.dimension), at<int>(game(), layout.game.roomIndex)};
    room->clock.reset(at<int>(game(), layout.game.frame));
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
                           (connectedMask & (1u << slot)) &&
                           index >= layout.roomDescriptor.minimumRoom && index < 169 &&
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
                (at<int>(actor, layout.player.controller) == static_cast<int>(owner + 1) ||
                 at<Address>(head, layout.player.twin) == actor ||
                 at<Address>(actor, layout.player.twin) == head))
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
            integer("index", room ? room->key.index : at<int>(game(), layout.game.roomIndex));
            integer("dimension",
                    room ? room->key.dimension : at<int>(game(), layout.game.dimension));
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
        ending = engine<ChestEnding>(bindings.entry.gameGetChestEnding)(false);
    }
    lua.pushInteger(L, ending);
    return 1;
}
int beginCinematic(lua_State* L) {
    const bool ready = runtime::replica() && enabled && !scopes.depth() &&
                       at<int>(game(), layout.game.stage) == 13 &&
                       at<int>(game(), layout.game.stageType) == 1;
    if (ready)
        pendingDogma = at<Address>(game(), layout.game.room);
    lua.pushBoolean(L, ready);
    return 1;
}
int beginFloor(lua_State* L) {
    const auto same = lua.checkInteger(L, 1), animation = lua.checkInteger(L, 2);
    const auto sourceRoom = lua.checkInteger(L, 3);
    const auto head = participant(runtime::localViewSlot());
    const bool ready = runtime::replica() && enabled && !scopes.depth() && head && !pendingStage &&
                       (same == 0 || same == 1) && animation >= 0 && animation <= 6 &&
                       sourceRoom >= layout.roomDescriptor.minimumRoom && sourceRoom < 169;
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
bool projectRemote(unsigned slot, const SavedLocation& p) {
    const auto head = participant(slot);
    Key key{p.dimension, p.index};
    auto found = loaded.find(key);
    if (found == loaded.end()) {
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        const auto descriptor =
            reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
                reinterpret_cast<void*>(game()), key.index, key.dimension));
        const auto data = descriptor ? at<Address>(descriptor, layout.roomDescriptor.data) : 0;
        if (!data)
            return false;
        auto room = std::make_unique<Room>();
        room->key = key;
        room->owned = true;
        room->replicaShell = true;
        room->pointer = reinterpret_cast<Address>(allocate(layout.room.size));
        std::memset(reinterpret_cast<void*>(room->pointer), 0, layout.room.size);
        engine<RoomCall>(bindings.entry.roomConstruct)(reinterpret_cast<void*>(room->pointer));
        // Inventory/cache setters can query Room::GetGridCollision even when
        // the actor is offscreen. A constructor-only shell has a null descriptor.
        // Borrow floor metadata without loading entities, grids or room entry AI.
        at<Address>(room->pointer, layout.room.descriptor) = descriptor;
        at<int>(room->pointer, layout.room.type) = at<int>(data, layout.roomConfig.type);
        // Native Init includes the border tiles in both grid dimensions.
        at<int>(room->pointer, layout.room.gridWidth) =
            at<unsigned char>(data, layout.roomConfig.width) + 2;
        at<int>(room->pointer, layout.room.gridHeight) =
            at<unsigned char>(data, layout.roomConfig.height) + 2;
        for (unsigned i = 0; i < contextOffsets.size(); ++i) {
            room->context[i] = readContext(i);
            if (contextOffsets[i] == layout.game.roomIndex)
                room->context[i] = key.index;
            else if (contextOffsets[i] == layout.game.dimension)
                room->context[i] = key.dimension;
        }
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
    return true;
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
                p.index < layout.roomDescriptor.minimumRoom || p.index >= 169 ||
                !std::isfinite(p.x) || !std::isfinite(p.y))
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
            if (slot != static_cast<unsigned>(runtime::localViewSlot()) && !projectRemote(slot, p))
                throw std::runtime_error("Remote replica room has no authoritative descriptor");
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
Address mainRoomDescriptor(int index) {
    using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
    return reinterpret_cast<Address>(
        engine<Desc>(bindings.entry.engineRoomsDesc)(reinterpret_cast<void*>(game()), index, 0));
}
int specialRoomTemplate(lua_State* L) {
    const auto& descriptor = layout.roomDescriptor;
    const auto& config = layout.roomConfig;
    const auto index = lua.checkInteger(L, 1), type = lua.checkInteger(L, 2);
    const auto variant = lua.checkInteger(L, 3), seed = lua.checkInteger(L, 4);
    bool valid = enabled && !runtime::replica() && !scopes.depth() && templateConfig &&
                 templateGame == game() && index >= 0 && index < 169 && type >= 1 &&
                 type <= config.maxType && variant >= config.anyVariant && variant <= INT_MAX &&
                 seed > 0 && seed <= UINT_MAX && !loaded.contains({0, static_cast<int>(index)});
    if (valid) {
        const auto desc = mainRoomDescriptor(static_cast<int>(index));
        const auto previous = desc ? at<Address>(desc, descriptor.data) : 0;
        valid = previous && !at<Address>(desc, descriptor.overrideData) &&
                !at<int>(desc, descriptor.visitedCount);
        if (valid) {
            const bool randomVariant = variant == config.anyVariant;
            const unsigned requiredDoors = at<unsigned>(desc, descriptor.allowedDoors);
            unsigned doors = requiredDoors;
            const auto shape = at<int>(previous, config.shape);
            const auto selected = reinterpret_cast<Address>(originalRandomRoom(
                templateConfig, static_cast<unsigned>(seed), false, config.specialStage,
                static_cast<int>(type), shape, randomVariant ? 0 : static_cast<int>(variant),
                static_cast<int>(variant), 0, config.maxDifficulty, &doors, -1,
                randomVariant ? config.normalMode : -1));
            valid = selected && at<int>(selected, config.type) == type &&
                    (randomVariant || at<int>(selected, config.variant) == variant) &&
                    at<int>(selected, config.shape) == shape &&
                    (at<unsigned>(selected, config.doors) & requiredDoors) == requiredDoors;
            // Borrow the game's immutable configuration. The descriptor and
            // spawn vectors keep their native owner; no copied MSVC containers.
            if (valid)
                at<Address>(desc, descriptor.data) = selected;
        }
    }
    lua.pushBoolean(L, valid);
    return 1;
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
                value.babySkin < -1 || value.babySkin > layout.player.lastBabySkin ||
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
                    engine<Remove>(bindings.entry.playerManagerRemovePlayer)(
                        reinterpret_cast<void*>(game() + layout.game.playerManager),
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
            if (at<unsigned>(parent, layout.player.controller) != value.controller)
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
                if (at<Address>(candidate, layout.entity.parent) == parent &&
                    at<unsigned>(candidate, layout.player.controller) == value.controller &&
                    at<unsigned>(candidate, layout.player.type) == value.kind)
                    body = candidate;
            }
            if (!body) {
                const auto view = findRoom(participant(runtime::localViewSlot()));
                if (!view || view->replicaShell)
                    throw std::runtime_error("Companion creation requires a loaded local room");
                {
                    Scope scope(*view, all);
                    using Spawn = void*(__attribute__((thiscall))*)(void*, int);
                    body = reinterpret_cast<Address>(engine<Spawn>(bindings.entry.playerSpawn)(
                        reinterpret_cast<void*>(game() + layout.game.playerManager), 0));
                    if (!body)
                        throw std::runtime_error("Cannot allocate companion actor");
                    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
                    engine<Assign>(bindings.entry.engineRoomsAssign)(reinterpret_cast<void*>(body),
                                                                     value.controller, false);
                    using AssignPtr = void*(__attribute__((thiscall))*)(void*, void*);
                    engine<AssignPtr>(bindings.entry.entityPtrAssignTwin)(
                        reinterpret_cast<void*>(body + layout.entity.parent),
                        reinterpret_cast<void*>(parent));
                    // Initialize a neutral native body, then restore its display
                    // form. Initializing a gameplay character here would create
                    // another Soul/twin or reroll starting items on the replica.
                    engine<RoomCall>(bindings.entry.playerInitialize)(
                        reinterpret_cast<void*>(body));
                    at<unsigned>(body, layout.player.type) = value.kind;
                    at<unsigned>(body, layout.entity.variant) = value.variant;
                }
                if (view != room)
                    moveEntity(body, *view, *room);
                location[body] = room;
                all = values(roster());
            }
            // Inventory cache evaluation recognizes native baby companions by
            // both variant and skin. Establish that identity before any parent
            // inventory setter can decide to allocate a second companion.
            at<int>(body, layout.player.babySkin) = value.babySkin;
            replicaCompanions[value.id] = body;
            const auto existing = std::find(all.begin(), all.end(), body);
            if (existing == all.end() || value.index >= all.size())
                throw std::runtime_error("Companion roster index is missing");
            all.erase(existing);
            all.insert(all.begin() + value.index, body);
        }
        assign(roster(), all);
        for (unsigned i = 0; i < all.size(); ++i)
            at<unsigned>(all[i], layout.player.index) = i;
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
            const auto kind = at<int>(owner, layout.player.type);
            const auto backup = at<Address>(owner, layout.player.lazarusBackup);
            auto room = findRoom(owner);
            if ((!compat::characters::lazarus(kind)) ||
                at<int>(owner, layout.player.controller) != controller || !room || !backup ||
                at<unsigned>(backup, layout.entity.type) != 1 ||
                at<int>(backup, layout.player.type) != desired ||
                at<Address>(backup, layout.player.lazarusBackup) != owner ||
                std::find(all.begin(), all.end(), backup) != all.end())
                continue;
            using AssignPtr = void*(__attribute__((thiscall))*)(void*, void*);
            using AddPlayer = void(__attribute__((thiscall))*)(void*, void*);
            {
                Scope scope(*room, all);
                engine<AssignPtr>(bindings.entry.entityPtrAssignTwin)(
                    reinterpret_cast<void*>(owner + layout.player.twin),
                    reinterpret_cast<void*>(backup));
                engine<AssignPtr>(bindings.entry.entityPtrAssignTwin)(
                    reinterpret_cast<void*>(backup + layout.player.twin),
                    reinterpret_cast<void*>(owner));
                at<Address>(owner, layout.player.lazarusBackup) =
                    at<Address>(backup, layout.player.lazarusBackup) = 0;
                at<int>(backup, layout.player.controller) = controller;
                at<bool>(backup, layout.entity.registered) =
                    at<bool>(backup, layout.entity.active) = true;
                at<Vec2>(backup, layout.entity.positionX) =
                    at<Vec2>(owner, layout.entity.positionX);
                engine<AddPlayer>(bindings.entry.playerManagerAddExistingPlayer)(
                    reinterpret_cast<void*>(game() + layout.game.playerManager),
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
    if (controller >= 0 && at<int>(old, layout.player.controller) != controller) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto kind = at<int>(old, layout.player.type);
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
    for (auto offset : {layout.player.twin, layout.player.lazarusBackup}) {
        const auto candidate = at<Address>(old, offset);
        if (candidate && at<unsigned>(candidate, layout.entity.type) == 1 &&
            at<int>(candidate, layout.player.type) == desired) {
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
        replaced = engine<Replace>(bindings.entry.playerManagerReplacePlayer)(
            reinterpret_cast<void*>(game() + layout.game.playerManager),
            reinterpret_cast<void*>(old), reinterpret_cast<void*>(replacement));
    }
    participants = logicalPlayers();
    const auto current = values(roster());
    const bool ready = replaced && static_cast<std::size_t>(index) < current.size() &&
                       at<int>(current[index], layout.player.type) == desired;
    if (ready)
        logger("actor_form=REPLACED index=" + std::to_string(index) +
               " type=" + std::to_string(desired));
    lua.pushBoolean(L, ready);
    return 1;
}
int actorLazarusUnpair(lua_State* L) {
    const auto index = lua.checkInteger(L, 1);
    const auto all = values(roster());
    if (!runtime::replica() || !enabled || scopes.depth() || index < 0 ||
        static_cast<std::size_t>(index) >= all.size()) {
        lua.pushBoolean(L, false);
        return 1;
    }

    const auto owner = all[index];
    const auto twin = at<Address>(owner, layout.player.twin);
    const auto room = findRoom(owner);
    const auto found = std::find(all.begin(), all.end(), twin);
    const bool valid =
        room && twin && found != all.end() && found - all.begin() > index &&
        findRoom(twin) == room && compat::characters::lazarus(at<int>(owner, layout.player.type)) &&
        compat::characters::lazarus(at<int>(twin, layout.player.type)) &&
        at<int>(twin, layout.player.type) != at<int>(owner, layout.player.type) &&
        !at<Address>(owner, layout.player.lazarusBackup) &&
        !at<Address>(twin, layout.player.lazarusBackup) &&
        at<Address>(twin, layout.player.twin) == owner &&
        at<int>(twin, layout.player.controller) == at<int>(owner, layout.player.controller);
    if (valid) {
        // Birthright disappears into the ghost inventory. Native Update then
        // demotes the listed twin to an owned, inactive backup (J511 0x382f0e),
        // which ghost conversion/revival traverses and actorForm can relist.
        Scope scope(*room, all);
        using Unlist = void(__attribute__((thiscall))*)(void*, void*);
        using AssignPtr = void*(__attribute__((thiscall))*)(void*, void*);
        at<Address>(owner, layout.player.lazarusBackup) = twin;
        at<Address>(twin, layout.player.lazarusBackup) = owner;
        engine<AssignPtr>(bindings.entry.entityPtrAssignTwin)(
            reinterpret_cast<void*>(twin + layout.player.twin), nullptr);
        engine<AssignPtr>(bindings.entry.entityPtrAssignTwin)(
            reinterpret_cast<void*>(owner + layout.player.twin), nullptr);
        at<bool>(twin, layout.entity.registered) = at<bool>(twin, layout.entity.active) = false;
        at<int>(twin, layout.player.index) = -1;
        engine<Unlist>(bindings.entry.playerManagerRemoveExistingPlayer)(
            reinterpret_cast<void*>(game() + layout.game.playerManager),
            reinterpret_cast<void*>(twin));
    }
    lua.pushBoolean(L, valid);
    return 1;
}
int actorForgottenForm(lua_State* L) {
    const auto desired = lua.checkInteger(L, 2);
    const auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
    if (!runtime::replica() || !enabled || !scopes.current() ||
        (desired != compat::ids::player::forgotten && desired != compat::ids::player::soul) ||
        !wrapper || lua.rawLength(L, 1) != 8 || wrapper[1] < layout.entity.sprite) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto player = wrapper[1] - layout.entity.sprite;
    const auto actors = values(roster());
    const bool listed = std::find(actors.begin(), actors.end(), player) != actors.end();
    const bool ready =
        listed && findRoom(player) == scopes.current() &&
        engine::native_forgotten_form::restore(
            bindings.forgotten, player, desired,
            engine<engine::native_forgotten_form::Swap>(bindings.entry.playerSwapForgottenForm));
    lua.pushBoolean(L, ready);
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
        engine<RoomCall>(ghost ? bindings.entry.replicaMorphToCoopGhost
                               : bindings.entry.replicaRevivePlayerGhost)(
            reinterpret_cast<void*>(all[index]));
    }
    lua.pushBoolean(L, true);
    return 1;
}
bool reviveGhost(Room& room, Address head) {
    Scope scope(room, controlledActors(head));
    engine<RoomCall>(bindings.entry.replicaRevivePlayerGhost)(reinterpret_cast<void*>(head));
    return !at<bool>(head, layout.player.coopGhost);
}
int revivePlayer(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    const auto head = slot >= 0 && slot < 4 ? participant(slot) : 0;
    const auto room = head ? findRoom(head) : nullptr;
    const bool valid = enabled && !runtime::replica() && !scopes.depth() && room &&
                       at<bool>(head, layout.player.coopGhost) && runtime::challengeActive() &&
                       runtime::allowChallengeEvent("round_revive");
    lua.pushBoolean(L, valid && reviveGhost(*room, head));
    return 1;
}
int coopRevive(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    std::string_view result = "unavailable";
    if (!runtime::replica() && stateReady() && slot >= 0 && slot < lan::maxPlayers) {
        const auto head = participant(slot);
        const auto room = head ? findRoom(head) : nullptr;
        if (!(connectedMask & (1u << slot)) || !head)
            result = "offline";
        else if (!runtime::allowChallengeEvent("coop_revive"))
            result = "forbidden";
        else if (room && !at<bool>(head, layout.player.coopGhost))
            result = "alive";
        else if (room && reviveGhost(*room, head))
            result = "revived";
    }
    lua.pushLString(L, result.data(), result.size());
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
RoomCall originalTntUpdate = nullptr;
void __attribute__((fastcall)) tntUpdate(void* tnt, void*) {
    // Native TNT owns an unsynchronized explosion countdown. Running it after
    // applying a replica snapshot can replay ReadyToExplode over Blown and
    // trigger another explosion. The host supplies state, collision and pose.
    if (!runtime::replica())
        originalTntUpdate(tnt);
}

void __attribute__((fastcall)) trapdoorUpdate(void* trapdoor, void*) {
    if (runtime::replica())
        return;
    const auto room = at<Address>(game(), layout.game.room);
    using IsClear = bool(__attribute__((thiscall))*)(void*);
    if (enabled && at<int>(room, layout.room.type) == 5 &&
        !engine<IsClear>(bindings.entry.roomIsClear)(reinterpret_cast<void*>(room))) {
        // Native trapdoors reopen from state zero when nobody stands nearby.
        // Keep the boss exit closed throughout combat, then let its normal
        // update open it and perform the floor transition after the clear.
        const auto grid = reinterpret_cast<Address>(trapdoor);
        at<int>(grid, layout.grid.state) = 0;
        using Play = void(__attribute__((thiscall))*)(void*, const char*, bool);
        engine<Play>(bindings.entry.spritePlay)(reinterpret_cast<void*>(grid + layout.grid.sprite),
                                                "Closed", false);
        return;
    }
    originalTrapdoorUpdate(trapdoor);
}
void __attribute__((fastcall)) replicaEntityUpdate(void* entity, void*) {
    const auto address = reinterpret_cast<Address>(entity);
    if (runtime::replica() &&
        !presentation::localAmbientEffect(at<unsigned>(address, layout.entity.type),
                                          at<unsigned>(address, layout.entity.variant),
                                          at<unsigned>(address, layout.entity.subtype))) {
        // Familiar::Render starts charging/disappear animations from the
        // replicated cooldown. Familiar::Update normally advances this owned
        // sprite; suppressing that UI update leaves the empty ring on screen.
        if (at<unsigned>(address, layout.entity.type) == 3)
            engine<RoomCall>(bindings.entry.spriteUpdate)(static_cast<char*>(entity) +
                                                          layout.familiar.chargeBar);
        return;
    }
    const auto entry = at<Address>(at<Address>(address, 0), layout.entity.updateMethod);
    entityUpdates.at(entry)(entity);
}
bool interceptReplicaEntities(Room& room) {
    // Preserve room cleanup, doors and background updates, while the server
    // owns entity gameplay. Native containers and allocation remain untouched.
    for (std::size_t offset : {layout.entityList.firstArray, layout.entityList.renderArray,
                               layout.entityList.effectArray}) {
        const auto list = room.pointer + layout.room.entities + offset;
        const auto data = at<Address>(list, layout.entityList.data),
                   count = at<unsigned>(list, layout.entityList.count);
        for (unsigned i = 0; i < count; ++i) {
            const auto entity = at<Address>(data, i * 4);
            if (at<unsigned>(entity, layout.entity.type) == 1)
                continue;
            const auto entry = at<Address>(at<Address>(entity, 0), layout.entity.updateMethod);
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
    for (std::size_t offset : {layout.entityList.firstArray, layout.entityList.renderArray,
                               layout.entityList.effectArray}) {
        const auto list = room + layout.room.entities + offset;
        for (unsigned i = 0; i < at<unsigned>(list, layout.entityList.count); ++i) {
            const auto entity = at<Address>(at<Address>(list, layout.entityList.data), i * 4);
            // Nighttime Home's TV spawns and immediately updates Dogma inside
            // its own update. Gather before that call, including debug damage,
            // so the original intro starts with the complete room roster.
            if (compat::bosses::finalCombat(
                    at<int>(game(), layout.game.stage), at<int>(game(), layout.game.stageType),
                    at<unsigned>(entity, layout.entity.type),
                    at<unsigned>(entity, layout.entity.variant), runtime::difficulty()))
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
            room->clock.advance(at<int>(game(), layout.game.frame), paused,
                                at<int>(room->pointer, layout.room.enteredFrame));
            if (paused)
                continue;
        }
        restorePositions(room->pointer);
        // Game::Update decrements this before Room::Update, outside our room
        // scopes. Each room restores its own value here, so advance it once
        // for every authoritative room. Delirium's death sequence waits for
        // this timer to reach zero before spawning the completion chest.
        auto& flash = at<int>(game(), layout.game.flashTimer);
        if (!runtime::replica() && flash > 0)
            --flash;
        if (at<bool>(game(), layout.game.shouldLerpColor)) {
            using Lerp = void(__attribute__((thiscall))*)(void*, const void*, const void*);
            engine<Lerp>(bindings.entry.colorModStateLerp)(
                reinterpret_cast<void*>(game() + layout.game.currentColor),
                reinterpret_cast<void*>(game() + layout.game.targetColor),
                reinterpret_cast<void*>(game() + layout.game.lerpColor));
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
        runtime::mapView(true);
        audio::present();
        presentation::pickup_preview::prepare();
        presentation::items::withScreen([&] {
            presentation::outlines::withPlayers(connected(), [&] {
                presentation::player_opacity::withPlayers(values(roster()), connected(), [&] {
                    combat_feedback::withPresentation(room->pointer, [&] { original(g); });
                });
            });
        });
        runtime::mapView(false);
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
    const auto manager = at<Address>(image, bindings.globalManager);
    const bool halfFrame = (at<unsigned>(manager, layout.manager.renderFrame) & 1u) != 0;
    // Replica packets restore authority positions before prediction. Advance
    // the native camera only after the visible local position is reconciled.
    Scope scope(*room, controlledActors(head));
    auto camera = reinterpret_cast<void*>(at<Address>(room->pointer, layout.room.camera));
    originalCameraSmooth(camera, halfFrame);
    at<bool>(reinterpret_cast<Address>(camera), layout.camera.focusOverride) = false;
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
        std::erase_if(players,
                      [&](Address p) { return at<int>(p, layout.player.controller) != slot + 1; });
    std::stable_partition(players.begin(), players.end(), [&](Address p) {
        return at<int>(p, layout.player.controller) == slot + 1;
    });
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
int currentRoomIndex() {
    return stateReady() ? at<int>(game(), layout.game.roomIndex) : -1;
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
    std::stable_sort(all.begin(), all.end(), [](Address a, Address b) {
        return at<int>(a, layout.player.controller) < at<int>(b, layout.player.controller);
    });
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
    return floorSource.room(at<int>(game(), layout.game.roomIndex));
}
bool receiveRoomRequest(unsigned slot, const lan::RoomRequest& request) {
    if (slot >= 4 || runtime::replica() || !stateReady() || !(connectedMask & (1u << slot)) ||
        at<int>(game(), layout.game.stage) != request.stage ||
        at<int>(game(), layout.game.stageType) != request.type)
        return false;
    const auto head = participant(slot);
    const auto from = findRoom(head);
    if (!from || from->key.index != request.source ||
        from->key.dimension != request.sourceDimension)
        return false;
    const auto target = destination(*from, request.destination, request.dimension);
    if (!target)
        return false;
    // Requests carry a validated source/destination, not the guest's native
    // EnterDoor. Reconstruct an unambiguous adjacent entrance on authority;
    // keeping source coordinates would land on the opposite wall of a resident
    // room. Teleports and cross-dimension transfers retain their native arrival.
    const int door =
        !request.teleport && target->index >= 0 && target->dimension == from->key.dimension
            ? uniqueEntranceDoor(from->key.index, entranceNeighbors(*target))
            : -1;
    if (door >= 0) {
        const int leave = uniqueEntranceDoor(target->index, entranceNeighbors(from->key));
        if (leave >= 0) {
            Scope scope(*from, controlledActors(head));
            at<int>(game(), layout.game.leaveDoor) = leave;
            // A guest's native door preview names the adjacent descriptor.
            // Resolve the actual transition on authority in the source room,
            // just as a host walking through that door would.
            constexpr int walkAnimation = 0;
            transition(reinterpret_cast<void*>(game()), nullptr, target->index, leave % 4,
                       walkAnimation, reinterpret_cast<void*>(head), target->dimension);
            return std::any_of(pending.begin(), pending.end(),
                               [head](const auto& value) { return value.player == head; });
        }
    }
    return queue(head, target->index, target->dimension, door, request.teleport);
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
        result.push_back({room->key.dimension, room->key.index,
                          at<float>(player, layout.entity.positionX),
                          at<float>(player, layout.entity.positionY)});
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
            parked.saved = {from->key.dimension, from->key.index,
                            at<float>(head, layout.entity.positionX),
                            at<float>(head, layout.entity.positionY)};
            parked.actors = controlledActors(head);
            parked.room = std::make_unique<Room>();
            parked.room->key = {0, -99};
            parked.room->owned = true;
            parked.room->pointer = reinterpret_cast<Address>(allocate(layout.room.size));
            engine<RoomCall>(bindings.entry.roomConstruct)(
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
            const Vec2 target{at<float>(host, layout.entity.positionX) + 12,
                              at<float>(host, layout.entity.positionY)};
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
                return at<int>(a, layout.player.controller) < at<int>(b, layout.player.controller);
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
        at<unsigned>(all[i], layout.player.index) = i;
    if (changed) {
        using GetHUD = void*(__attribute__((thiscall))*)(void*);
        engine<RoomCall>(bindings.entry.hudAssignPlayers)(
            engine<GetHUD>(bindings.entry.engineRoomsGetHUD)(reinterpret_cast<void*>(game())));
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
                engine<Cooldown>(bindings.entry.engineRoomsCooldown)(reinterpret_cast<void*>(actor),
                                                                     90);
        }
}
unsigned connected() {
    return connectedMask;
}
unsigned soundAudience() {
    if (!enabled)
        return 0;
    const auto current = at<Address>(game(), layout.game.room);
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
        if (runtime::replica() && slot != static_cast<unsigned>(runtime::localViewSlot()) &&
            !projectRemote(slot, saved[slot]))
            return false;
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
            runtime::roomLeaving();
        }
        collect();
    }

    void prepare(std::optional<engine::native_room_routing::RoomArrival> resolved = std::nullopt) {
        std::array<std::uint32_t, engine::native_rooms::contextFieldCount> nativeContext{};
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
                nativeContext[i] = readContext(i);
        }
        auto found = loaded.find(request.destination);
        created = found == loaded.end() || found->second->replicaShell;
        if (found == loaded.end()) {
            auto room = std::make_unique<Room>();
            room->pointer = reinterpret_cast<Address>(allocate(layout.room.size));
            room->owned = true;
            engine<RoomCall>(bindings.entry.roomConstruct)(reinterpret_cast<void*>(room->pointer));
            room->key = request.destination;
            room->context = from->context;
            to = room.get();
            loaded.emplace(request.destination, std::move(room));
        } else {
            to = found->second.get();
            if (to->replicaShell) {
                to->context = from->context;
                // A storage shell owns no backdrop surfaces. Promotion must
                // initialize graphics even after native inventory setters ran.
                to->graphicsRefresh = true;
                to->sceneSnapshot = 0;
            }
        }
        protect = !created && occupiedCombat(*to, request.player);
        std::optional<std::array<float, 2>> residentPosition;
        if (!created) {
            const auto residents = occupants(*to);
            if (!residents.empty()) {
                const auto position = at<Vec2>(residents.front(), layout.entity.positionX);
                residentPosition = {position.x, position.y};
            }
        }
        const auto certificatePosition = compat::items::deathCertificateArrival(
            request.animation, from->key.dimension, to->key.dimension, residentPosition);
        landing = request.landing ? request.landing
                  : certificatePosition
                      ? std::optional<Vec2>{{(*certificatePosition)[0], (*certificatePosition)[1]}}
                      : std::nullopt;
        if (!landing && request.door < 0 && residentPosition) {
            // Every non-door arrival into a resident room bypasses native
            // Init, including a second player taking the same staircase.
            // Source coordinates can lie beyond the destination's bounds;
            // reuse a destination-space position unless the caller supplied one.
            landing = Vec2{(*residentPosition)[0], (*residentPosition)[1]};
        }
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
            if (!created ||
                at<unsigned>(entity, layout.entity.type) != compat::characters::darkEsau) {
                moveEntity(entity, *from, *to);
                if (at<unsigned>(entity, layout.entity.type) == 867) {
                    using Persistent = void(__attribute__((thiscall))*)(void*, void*);
                    engine<Persistent>(bindings.entry.engineRoomsAddPersistent)(
                        reinterpret_cast<void*>(to->pointer + layout.room.entities),
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
                // return (J511 0x33fd70); preserve the native context.
                at<int>(game(), layout.game.deathCertificateRoom) = from->key.index;
                at<unsigned char>(game(), layout.game.deathCertificateDimension) =
                    from->key.dimension;
                at<int>(game(), layout.game.certificatePreviousRoom) =
                    at<int>(game(), layout.game.previousRoomIndex);
                at<unsigned char>(game(), layout.game.certificatePreviousDimension) =
                    at<int>(game(), layout.game.previousDimension);
                at<int>(game(), layout.game.certificateLeaveDoor) =
                    at<int>(game(), layout.game.leaveDoor);
            } else if (from->key.dimension == 2 && request.destination.dimension != 2) {
                // The activating player may have been in another
                // normal room. The authority's resolved return wins.
                at<int>(game(), layout.game.deathCertificateRoom) = request.destination.index;
                at<unsigned char>(game(), layout.game.deathCertificateDimension) =
                    request.destination.dimension;
            }
        }
        // Explicit replica/restoration destinations are never re-routed.
        at<int>(game(), layout.game.leaveDoor) = -1;
        at<int>(game(), layout.game.enterDoor) = request.door;
        const auto curseBase = at<std::uint32_t>(game(), layout.game.curses);
        const auto curseSeeds = at<std::uint32_t>(game(), layout.game.seedCurses);
        auto change = [&] {
            engine::native_room_routing::withResolvedRoomEntry(
                [&](engine::native_room_routing::RoomArrival) {
                    // Explicit transfers suppress LeaveDoor rerouting. Native
                    // resolution can then choose a fallback entrance; restore
                    // the accepted door before Room::Init constructs its exits.
                    if (request.door >= 0 && request.door < 8)
                        at<int>(game(), layout.game.enterDoor) = request.door;
                    return true;
                },
                [&] {
                    originalChange(reinterpret_cast<void*>(game()), request.destination.index,
                                   request.destination.dimension);
                });
        };
        if (runtime::replica() || restoringSavedLocations ||
            request.routing == RoomRouting::resolved)
            engine::native_room_routing::withoutRoomCurseRouting(change);
        else
            change();
        logger("room_change requested=" + std::to_string(request.destination.index) +
               " actual=" + std::to_string(at<int>(game(), layout.game.roomIndex)) +
               " curse_base=" + std::to_string(curseBase) +
               " curse_seeds=" + std::to_string(curseSeeds));
    }

    void arrive() {
        // Native Maze may select a covered grid cell of a large room. Keep
        // that entry context, but compare identity through its descriptor.
        const auto actual = destination(*to, at<int>(game(), layout.game.roomIndex),
                                        at<int>(game(), layout.game.dimension));
        if (!actual || *actual != to->key)
            throw std::runtime_error("Native room entry differs from its registered destination");
        if (created) {
            if (!runtime::replica())
                engine<RoomCall>(bindings.entry.roomUpdateMusic)(
                    reinterpret_cast<void*>(to->pointer));
            for (auto entity : companions)
                if (at<unsigned>(entity, layout.entity.type) == compat::characters::darkEsau)
                    moveEntity(entity, *from, *to);
        } else {
            // Joining an occupied room must apply the arriving characters'
            // entry effects without reinitializing resident entities.
            for (auto player : actors) {
                clearRoomTransitionTarget(player);
                engine<RoomCall>(bindings.entry.playerNewRoom)(reinterpret_cast<void*>(player));
            }
            for (auto entity : companions)
                if (at<unsigned>(entity, layout.entity.type) == 3)
                    bindings.familiarNewRoom(image, entity);
        }
        for (auto entity : companions) {
            // Dark Esau is transferred after native Init, so its own room
            // entry must run here even for a newly loaded destination. Keep
            // the original NPC and let native entry translate its pursuit
            // position; placing it at the player's landing causes a hit.
            const auto type = at<unsigned>(entity, layout.entity.type);
            const bool esau = compat::characters::taintedJacobPursuer(
                type, at<unsigned>(entity, layout.entity.variant));
            if ((esau && !runtime::replica()) ||
                (type == compat::ids::entity::mothersShadow && !created)) {
                auto& previousIndex = at<int>(game(), layout.game.previousRoomIndex);
                auto& previousDimension = at<int>(game(), layout.game.previousDimension);
                const auto savedIndex = previousIndex, savedDimension = previousDimension;
                previousIndex = from->key.index;
                previousDimension = from->key.dimension;
                engine<RoomCall>(bindings.entry.engineRoomsNPCNewRoom)(
                    reinterpret_cast<void*>(entity));
                previousIndex = savedIndex;
                previousDimension = savedDimension;
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
                if (at<unsigned>(entity, layout.entity.type) == 3)
                    engine<RoomCall>(bindings.entry.familiarResetRoomState)(
                        reinterpret_cast<void*>(entity));
        }
        runtime::roomEntered(request.door);
        if (created) {
            to->clock.reset(at<int>(game(), layout.game.frame));
        }
        presentation::roomEntered(to->pointer, created);
        if (!created) {
            // J511's native POST_NEW_ROOM dispatcher (callback 19). A
            // resident room needs the entry notification without Init;
            // local Mod interfaces must not keep the departure descriptor.
            engine<PostUpdate>(bindings.entry.luaPostNewRoom)();
        }
        if (request.teleport) {
            using Animate = void(__attribute__((thiscall))*)(void*, bool);
            for (auto p : actors) {
                engine<Animate>(bindings.entry.playerAnimateTeleport)(reinterpret_cast<void*>(p),
                                                                      false);
            }
        }
        // The native minecart (animation 19) also disables controls. Only
        // its arriving actors receive the native completion; residents in
        // another room keep their own control and animation state.
        for (auto p : actors)
            completeArrivalControls(request.animation, at<bool>(p, layout.player.controlsEnabled),
                                    controlRestoreState());
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
            at<int>(game(), layout.game.leaveDoor) = -1;
            at<int>(game(), layout.game.enterDoor) = request.door;
            {
                NativeTransfer nativeTransfer;
                engine::native_room_routing::withResolvedRoomEntry(
                    [&](engine::native_room_routing::RoomArrival resolved) {
                        prepare(resolved);
                        scope.enter(*to);
                        if (request.door >= 0 && request.door < 8)
                            at<int>(game(), layout.game.enterDoor) = request.door;
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
        if (!runtime::replica() && !restoringSavedLocations && from->key != to->key)
            previousSeatRoom[slotOf(request.player)] = from->key;
        canonical();
        logger("room_transfer slot=" + std::to_string(slotOf(request.player)) +
               " from=" + std::to_string(from->key.index) + " to=" + std::to_string(to->key.index) +
               " created=" + std::to_string(created) + " entry=" + std::to_string(request.door) +
               " x=" + std::to_string(at<float>(request.player, layout.entity.positionX)) +
               " y=" + std::to_string(at<float>(request.player, layout.entity.positionY)));
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
    if (resumeStage && !enabled && at<int>(game(), layout.game.stageTransition) == 0 &&
        at<int>(game(), layout.game.roomTransition) == 0) {
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
            logger("floor_transaction=COMPLETE stage=" +
                   std::to_string(at<int>(game(), layout.game.stage)));
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
            bindings.beginDogmaCinematic(image);
        }
        originalTransition(reinterpret_cast<void*>(game()), -10, -1, 1, nullptr, -1);
        originalNativeRoomChange(reinterpret_cast<void*>(game() + layout.game.roomTransition));
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
        std::vector<std::string> departureAnimations;
        if (!runtime::replica()) {
            // Native light effects omit the actor when several players share
            // the source room. Capture its active poses after the native call
            // has started them, before dismantling that room.
            auto players =
                request.player ? std::vector<Address>{request.player} : std::vector<Address>{};
            if (!request.player) {
                for (const auto& [key, room] : loaded)
                    if (key.index == request.sourceRoom && key.dimension == request.sourceDimension)
                        players = occupants(*room);
            }
            for (const auto player : players) {
                auto name = visuals::actorDepartureAnimation(player);
                if (!name.empty() &&
                    std::find(departureAnimations.begin(), departureAnimations.end(), name) ==
                        departureAnimations.end())
                    departureAnimations.push_back(std::move(name));
            }
        }
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
            engine<ChestEnding>(bindings.entry.gameGetChestEnding)(false) == 0)
            runtime::beginStage(request.same, request.animation, 0, 0, departureAnimations);
        // Replicas never simulate the chest collector or its grid markers.
        // Use the ordinary floor entry rather than waiting for local markers
        // and re-evaluating the chest against replica unlocks/inventory. J511
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
            const auto position = at<Vec2>(player, layout.entity.positionX);
            actors[count++] = {slot,
                               room->key.dimension,
                               room->key.index,
                               at<bool>(player, layout.player.coopGhost),
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
    if (pending.empty() && pendingArrivalRecovery.empty()) {
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
        if (request.teleport && request.animateDeparture &&
            at<bool>(request.player, layout.player.extraAnimationActive) &&
            !engine<Finished>(bindings.entry.spriteIsFinished)(
                reinterpret_cast<void*>(request.player + layout.entity.sprite), "")) {
            pending.push_back(request);
            continue;
        }
        using Desc = void*(__attribute__((thiscall))*)(void*, int, int);
        auto desc = reinterpret_cast<Address>(engine<Desc>(bindings.entry.engineRoomsDesc)(
            reinterpret_cast<void*>(game()), request.destination.index,
            request.destination.dimension));
        if (!desc || !at<Address>(desc, layout.roomDescriptor.data)) {
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
            engine::native_room_routing::currentCurses()));
    }
    preparedDepartures.clear();
    if (beginTeamTransition)
        beginTeamTransition();
    for (auto slot : pendingArrivalRecovery)
        if (const auto head = participant(slot)) {
            for (auto player : controlledActors(head)) {
                // Same visibility exclusion as native RoomTransition::ChangeRoom.
                if (!(at<unsigned>(player, layout.entity.flagsHigh) & 0x02000000u))
                    at<bool>(player, layout.entity.visible) = true;
                using Cooldown = void(__attribute__((thiscall))*)(void*, int);
                engine<Cooldown>(bindings.entry.engineRoomsCooldown)(
                    reinterpret_cast<void*>(player), 90);
            }
        }
    pendingArrivalRecovery.clear();
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
    const auto manager = at<Address>(image, bindings.globalManager);
    at<bool>(manager, layout.manager.deleteSaveRequested) = save;
    at<int>(manager, layout.manager.requestedMenu) = 2;
    using Transition = void(__attribute__((thiscall))*)(void*, int);
    engine<Transition>(bindings.entry.colorConstruct)(
        reinterpret_cast<void*>(manager + layout.manager.menuTransition), -1);
    at<bool>(manager, layout.manager.menuRequested) = true;
}
void finishChallenge() {
    // LAN challenges keep Game::Challenge at zero: use the original fade/menu
    // flow while skipping native challenge unlocks. Existing save guards cover
    // FinishChallenge's attempt to remove the single-player Continue file.
    reinterpret_cast<RoomCall>(image +
                               bindings.entry.gameFinishChallenge)(reinterpret_cast<void*>(game()));
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
    previousSeatRoom.fill(std::nullopt);
    replicaCompanions.clear();
    floorSource.reset();
    replicaDeals.reset();
    presentation::items::reset(preserveItemPixels);
    engine::native_room_data::resetMap();
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
    const auto source = at<Address>(game(), layout.game.room);
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
    pendingArrivalRecovery.clear();
    Room* root = nullptr;
    for (auto& [key, room] : loaded) {
        (void)key;
        if (room->pointer == at<Address>(game(), layout.game.room))
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
    engine::native_room_data::withMapPickups(cache);
}
bool install(Address base, void (*log)(const std::string&)) {
    image = base;
    logger = log;
    if (!lua.load(GetModuleHandleW(L"Lua5.3.3r.dll"),
                  {isaac::lua::Symbol::getTop, isaac::lua::Symbol::setTop}))
        return false;
    auto hook = [](Address rva, void* replacement, void** original) {
        return MH_CreateHook(reinterpret_cast<void*>(image + rva), replacement, original) ==
                   MH_OK &&
               MH_EnableHook(reinterpret_cast<void*>(image + rva)) == MH_OK;
    };
    return engine::native_room_routing::installRoomRouting(image) &&
           bindings.installStageBinding(image, lua) &&
           hook(bindings.entry.levelSwapRooms, reinterpret_cast<void*>(swapRooms),
                reinterpret_cast<void**>(&originalSwapRooms)) &&
           hook(bindings.entry.entityPlayerAddCoins, reinterpret_cast<void*>(addCoins),
                reinterpret_cast<void**>(&originalCoins)) &&
           hook(bindings.entry.playerManagerFindCollectible,
                reinterpret_cast<void*>(findCollectible),
                reinterpret_cast<void**>(&originalFindCollectible)) &&
           hook(bindings.entry.playerManagerCollectibleCount,
                reinterpret_cast<void*>(collectibleCount),
                reinterpret_cast<void**>(&originalCollectibleCount)) &&
           engine::native_room_queries::install(image, withTypeQuery) &&
           hook(bindings.entry.itemPoolGetCardEx, reinterpret_cast<void*>(getCardEx),
                reinterpret_cast<void**>(&originalGetCardEx)) &&
           hook(bindings.entry.roomConfigRandomRoom, reinterpret_cast<void*>(randomRoom),
                reinterpret_cast<void**>(&originalRandomRoom)) &&
           hook(bindings.entry.roomGetDevilRoomChance, reinterpret_cast<void*>(dealTotal),
                reinterpret_cast<void**>(&originalDealTotal)) &&
           hook(bindings.entry.dealAngelShare, reinterpret_cast<void*>(isaac_lan_angel_share_thunk),
                &originalAngelShare) &&
           hook(bindings.entry.levelInitializeDevilAngelRoom,
                reinterpret_cast<void*>(initializeDeals),
                reinterpret_cast<void**>(&originalInitializeDeals)) &&
           hook(bindings.entry.roomTrySpawnDevilRoomDoor, reinterpret_cast<void*>(spawnDeals),
                reinterpret_cast<void**>(&originalSpawnDeals)) &&
           hook(bindings.entry.playerManagerReplacePlayer, reinterpret_cast<void*>(replacePlayer),
                reinterpret_cast<void**>(&originalReplacePlayer)) &&
           hook(bindings.entry.playerTriggerRoomClear, reinterpret_cast<void*>(playerRoomClear),
                reinterpret_cast<void**>(&originalPlayerRoomClear)) &&
           hook(bindings.entry.entityPlayerSyncResources, reinterpret_cast<void*>(syncResources),
                reinterpret_cast<void**>(&originalResources)) &&
           hook(bindings.entry.gameEnd, reinterpret_cast<void*>(endGame),
                reinterpret_cast<void**>(&originalEnd)) &&
           hook(bindings.entry.engineRoomsSave, reinterpret_cast<void*>(save),
                reinterpret_cast<void**>(&originalSave)) &&
           hook(bindings.entry.engineRoomsChange, reinterpret_cast<void*>(change),
                reinterpret_cast<void**>(&originalChange)) &&
           hook(bindings.entry.roomTransitionUpdate, reinterpret_cast<void*>(nativeRoomChange),
                reinterpret_cast<void**>(&originalNativeRoomChange)) &&
           hook(bindings.entry.engineRoomsTransition, reinterpret_cast<void*>(transition),
                reinterpret_cast<void**>(&originalTransition)) &&
           (!bindings.entry.roomTransitionStart ||
            hook(*bindings.entry.roomTransitionStart, reinterpret_cast<void*>(startRoomTransition),
                 reinterpret_cast<void**>(&originalRoomTransitionStart))) &&
           hook(bindings.entry.engineRoomsStageTransition, reinterpret_cast<void*>(stageTransition),
                reinterpret_cast<void**>(&originalStage)) &&
           hook(bindings.entry.levelSetNextStage, reinterpret_cast<void*>(nextStage),
                reinterpret_cast<void**>(&originalNextStage)) &&
           hook(bindings.entry.gameTriggerRKey, reinterpret_cast<void*>(rKey),
                reinterpret_cast<void**>(&originalRKey)) &&
           hook(bindings.entry.gameNextVictoryLap, reinterpret_cast<void*>(victoryLap),
                reinterpret_cast<void**>(&originalVictoryLap)) &&
           hook(bindings.entry.engineRoomsIsCoop, reinterpret_cast<void*>(isCoop),
                reinterpret_cast<void**>(&originalIsCoop)) &&
           hook(bindings.entry.engineRoomsLiving, reinterpret_cast<void*>(living),
                reinterpret_cast<void**>(&originalLiving)) &&
           (!bindings.entry.engineRoomsDead ||
            hook(*bindings.entry.engineRoomsDead, reinterpret_cast<void*>(dead),
                 reinterpret_cast<void**>(&originalDead))) &&
           hook(bindings.entry.playerManagerReviveCoop, reinterpret_cast<void*>(reviveAll),
                reinterpret_cast<void**>(&originalReviveAll)) &&
           hook(bindings.entry.engineRoomsAward, reinterpret_cast<void*>(award),
                reinterpret_cast<void**>(&originalAward)) &&
           hook(bindings.entry.engineRoomsExitGame, reinterpret_cast<void*>(exitGame),
                reinterpret_cast<void**>(&originalExit)) &&
           hook(bindings.entry.engineRoomsLeaveRoom, reinterpret_cast<void*>(leaveRoom),
                reinterpret_cast<void**>(&originalLeave)) &&
           hook(bindings.entry.cameraSmooth, reinterpret_cast<void*>(cameraSmooth),
                reinterpret_cast<void**>(&originalCameraSmooth)) &&
           hook(bindings.entry.cameraDrag, reinterpret_cast<void*>(cameraDrag),
                reinterpret_cast<void**>(&originalCameraDrag)) &&
           hook(bindings.entry.playerManagerGetCenter, reinterpret_cast<void*>(playersCenter),
                reinterpret_cast<void**>(&originalPlayersCenter)) &&
           hook(bindings.entry.doorUpdate, reinterpret_cast<void*>(doorUpdate),
                reinterpret_cast<void**>(&originalDoorUpdate)) &&
           hook(bindings.entry.gridEntityTrapdoorUpdate, reinterpret_cast<void*>(trapdoorUpdate),
                reinterpret_cast<void**>(&originalTrapdoorUpdate)) &&
           hook(bindings.entry.gridEntityTntUpdate, reinterpret_cast<void*>(tntUpdate),
                reinterpret_cast<void**>(&originalTntUpdate)) &&
           hook(bindings.entry.nPCNeedlePrepareVisual, reinterpret_cast<void*>(needleVisual),
                reinterpret_cast<void**>(&originalNeedleVisual)) &&
           hook(bindings.entry.engineRoomsPostUpdate, reinterpret_cast<void*>(postUpdate),
                reinterpret_cast<void**>(&originalPostUpdate)) &&
           hook(bindings.entry.luaPostNewRoom, reinterpret_cast<void*>(postNewRoom),
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
    function("room_special_template", specialRoomTemplate);
    function("actor_form", actorForm);
    function("actor_lazarus_unpair", actorLazarusUnpair);
    function("actor_forgotten_form", actorForgottenForm);
    function("actor_companions", actorCompanions);
    function("actor_ghost", actorGhost);
    function("rooms_revive_player", revivePlayer);
    function("rooms_coop_revive", coopRevive);
    function("rooms_set_connected", setConnections);
    function("rooms_connected", connections);
    function("rooms_begin_floor", beginFloor);
    function("rooms_begin_cinematic", beginCinematic);
    return engine::native_room_data::bind(L, module, image,
                                          {[] { return enabled; }, [] { return !scopes.depth(); },
                                           [] {
                                               const auto room = scopes.current();
                                               return enabled && room && !room->replicaShell
                                                          ? room->pointer
                                                          : 0;
                                           }}) &&
           engine::native_actor_state::bind(
               L, module, image, {[](bool team) {
                   return values(team && scopes.teamRoster() ? *scopes.teamRoster() : roster());
               }}) &&
           engine::native_laser_state::bind(L, module, image) && visuals::bind(L, module);
}
} // namespace isaac::rooms

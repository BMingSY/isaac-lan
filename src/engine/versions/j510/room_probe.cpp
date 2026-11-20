#include "engine/versions/j510/room_probe.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"
#include "core/level_grid.h"
#include <array>
#include <cstdio>
#include <cstring>

namespace isaac::engine::j510 {
namespace {
namespace layout = j510::layout;
using native_bootstrap::Address;
Address image;
native_bootstrap::Logger log;
lua::API lua;
constexpr Address gamePointerRva = globals::game;
template <class T> T& field(Address base, std::size_t offset) {
    return *reinterpret_cast<T*>(base + offset);
}
template <class T> T engine(Address rva) {
    return reinterpret_cast<T>(image + rva);
}
using NativeRoomCall = rooms::RoomCall;
using NativeRoomInit = void(__attribute__((thiscall)) *)(void*, void*, void*);
using NativeGetDesc = void*(__attribute__((thiscall)) *)(void*, int, int);
Address backgroundRoom = 0;
int backgroundIndex = -1, roomSteps = 0;
bool roomScopeActive = false;
unsigned foregroundNativeUpdates = 0, backgroundNativeUpdates = 0;
unsigned foregroundHalfUpdates = 0, backgroundHalfUpdates = 0;

void movePlayer(std::uintptr_t player, std::uintptr_t from, std::uintptr_t to) {
    for (std::size_t offset = layout::entityList::firstArray;
         offset <= layout::entityList::lastArray; offset += layout::entityList::arrayStride) {
        const auto list = from + layout::room::entities + offset;
        auto data = reinterpret_cast<std::uintptr_t*>(
            field<std::uintptr_t>(list, layout::entityList::data));
        auto& size = field<unsigned>(list, layout::entityList::count);
        for (unsigned i = 0; i < size;) {
            if (data[i] != player) {
                ++i;
                continue;
            }
            memmove(data + i, data + i + 1, (size - i - 1) * sizeof(*data));
            --size;
        }
    }
    using InvalidateQuery = void(__attribute__((thiscall))*)(void*, unsigned, unsigned, unsigned);
    engine<InvalidateQuery>(j510::entry::engineRoomsInvalidate)(
        reinterpret_cast<void*>(from + layout::room::entities), 1, 0, 0);
    field<bool>(player, layout::entity::registered) = false;
    field<unsigned>(player, layout::entity::index) =
        field<unsigned>(to, layout::room::nextEntityIndex)++;
    using Add = void(__attribute__((thiscall))*)(void*, void*);
    engine<Add>(j510::entry::engineRoomsAdd)(reinterpret_cast<void*>(to + layout::room::entities),
                                             reinterpret_cast<void*>(player));
}

struct RoomScope {
    std::uintptr_t game;
    std::uintptr_t originalRoom;
    int originalIndex, originalDimension;
    std::array<std::uintptr_t, layout::vector::words> players;
    explicit RoomScope(std::uintptr_t g) : game(g) {
        originalRoom = field<std::uintptr_t>(g, layout::game::room);
        originalIndex = field<int>(g, layout::game::roomIndex);
        originalDimension = field<int>(g, layout::game::dimension);
        memcpy(players.data(), reinterpret_cast<void*>(g + layout::game::players), sizeof(players));
        field<std::uintptr_t>(g, layout::game::room) = backgroundRoom;
        field<int>(g, layout::game::roomIndex) = backgroundIndex;
        field<int>(g, layout::game::dimension) = 0;
        // Keep the game's own backing allocation. This experiment requires two
        // ordinary players and exposes only player two during background work.
        field<std::uintptr_t>(g, layout::game::players) = players[0] + sizeof(std::uintptr_t);
        field<std::uintptr_t>(g, layout::game::players + layout::vector::end) =
            players[0] + 2 * sizeof(std::uintptr_t);
        roomScopeActive = true;
    }
    ~RoomScope() {
        if (field<std::uintptr_t>(game, layout::game::players) !=
                players[0] + sizeof(std::uintptr_t) ||
            field<std::uintptr_t>(game, layout::game::players + layout::vector::capacity) !=
                players[2]) {
            log("room_scope=FAIL player_vector_reallocated");
            TerminateProcess(GetCurrentProcess(), 91);
        }
        memcpy(reinterpret_cast<void*>(game + layout::game::players), players.data(),
               sizeof(players));
        field<std::uintptr_t>(game, layout::game::room) = originalRoom;
        field<int>(game, layout::game::roomIndex) = originalIndex;
        field<int>(game, layout::game::dimension) = originalDimension;
        roomScopeActive = false;
    }
    RoomScope(const RoomScope&) = delete;
};

void initialize(Address base, native_bootstrap::Logger logger) {
    image = base;
    log = logger;
}
bool update(void* room, NativeRoomCall original) {
    if (!backgroundRoom || roomScopeActive || reinterpret_cast<Address>(room) == backgroundRoom)
        return false;
    const auto game = field<Address>(image, gamePointerRva);
    const auto begin = field<Address>(game, layout::game::players);
    auto& end = field<Address>(game, layout::game::players + layout::vector::end);
    {
        struct RestoreEnd {
            Address& end;
            Address saved;
            ~RestoreEnd() {
                end = saved;
            }
        } restore{end, end};
        end = begin + sizeof(Address);
        original(room);
    }
    ++foregroundNativeUpdates;
    RoomScope context(game);
    native_bootstrap::restoreRoomPositions(backgroundRoom);
    original(reinterpret_cast<void*>(backgroundRoom));
    ++backgroundNativeUpdates;
    return true;
}
bool render(void* game, NativeRoomCall original, int slot) {
    if (!backgroundRoom || roomScopeActive || slot != 1)
        return false;
    RoomScope context(reinterpret_cast<Address>(game));
    original(game);
    return true;
}
void half(native_bootstrap::HalfUpdate original) {
    if (!backgroundRoom || roomScopeActive)
        return;
    ++foregroundHalfUpdates;
    RoomScope context(field<Address>(image, gamePointerRva));
    original();
    ++backgroundHalfUpdates;
}
bool active() {
    return roomScopeActive;
}

void describeRoom(const char* name, std::uintptr_t room) {
    auto list = room + layout::room::entities + layout::entityList::firstArray;
    auto data = field<std::uintptr_t>(list, layout::entityList::data);
    auto count = field<unsigned>(list, layout::entityList::count);
    char line[256];
    snprintf(line, sizeof(line), "%s room=%08lx count=%u", name, static_cast<unsigned long>(room),
             count);
    log(line);
    constexpr unsigned maxAuditedEntities = 2000, maxLoggedEntities = 30;
    if (count > maxAuditedEntities)
        return;
    for (unsigned i = 0; i < count && i < maxLoggedEntities; ++i) {
        auto entity = field<std::uintptr_t>(data, i * sizeof(std::uintptr_t));
        snprintf(line, sizeof(line), " entity=%08lx type=%u variant=%u",
                 static_cast<unsigned long>(entity), field<unsigned>(entity, layout::entity::type),
                 field<unsigned>(entity, layout::entity::variant));
        log(line);
    }
}

int createRoom(lua_State* L) {
    const int index = static_cast<int>(lua.checkInteger(L, 1));
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    if (backgroundRoom || roomScopeActive || index < 0 || index >= level_grid::cellCount ||
        field<int>(game, layout::game::roomIndex) == index ||
        field<std::uintptr_t>(game, layout::game::players + layout::vector::end) -
                field<std::uintptr_t>(game, layout::game::players) !=
            8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto desc = reinterpret_cast<std::uintptr_t>(engine<NativeGetDesc>(
        j510::entry::engineRoomsDesc)(reinterpret_cast<void*>(game), index, 0));
    if (!desc || !field<std::uintptr_t>(desc, layout::roomDescriptor::data)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    log("room_create=BEGIN");
    roomSteps = 0;
    foregroundNativeUpdates = backgroundNativeUpdates = 0;
    foregroundHalfUpdates = backgroundHalfUpdates = 0;
    using Allocate = void*(__cdecl*)(std::size_t);
    backgroundRoom = reinterpret_cast<std::uintptr_t>(
        engine<Allocate>(j510::entry::engineRoomsAllocate)(layout::room::size));
    if (!backgroundRoom) {
        lua.pushBoolean(L, false);
        return 1;
    }
    engine<NativeRoomCall>(j510::entry::engineRoomsRoomCall_3e9400)(
        reinterpret_cast<void*>(backgroundRoom));
    backgroundIndex = index;
    {
        RoomScope context(game);
        engine<NativeRoomInit>(j510::entry::probeNativeRoomInit)(
            reinterpret_cast<void*>(backgroundRoom),
            reinterpret_cast<void*>(field<std::uintptr_t>(desc, layout::roomDescriptor::data)),
            reinterpret_cast<void*>(desc));
        auto player = field<std::uintptr_t>(field<std::uintptr_t>(game, layout::game::players), 0);
        movePlayer(player, context.originalRoom, backgroundRoom);
    }
    describeRoom("foreground_after_init", field<std::uintptr_t>(game, layout::game::room));
    describeRoom("background_after_init", backgroundRoom);
    log("room_create=RETURNED");
    lua.pushBoolean(L, true);
    return 1;
}

int finishRooms(lua_State* L) {
    if (!backgroundRoom || roomScopeActive) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    auto foreground = field<std::uintptr_t>(game, layout::game::room);
    auto player = field<std::uintptr_t>(field<std::uintptr_t>(game, layout::game::players), 4);
    movePlayer(player, backgroundRoom, foreground);
    // Native destructor owns native container allocations; native sized delete
    // releases the object from the same allocator used during construction.
    engine<NativeRoomCall>(j510::entry::engineRoomsRoomCall_3e9ba0)(
        reinterpret_cast<void*>(backgroundRoom));
    using Delete = void(__cdecl*)(void*, std::size_t);
    engine<Delete>(j510::entry::engineRoomsDelete)(reinterpret_cast<void*>(backgroundRoom),
                                                   layout::room::size);
    backgroundRoom = 0;
    log("room_cleanup=RETURNED");
    lua.pushBoolean(L, true);
    return 1;
}

int withRoom(lua_State* L) {
    if (!backgroundRoom || roomScopeActive) {
        lua.pushBoolean(L, false);
        return 1;
    }
    int status;
    {
        RoomScope context(field<std::uintptr_t>(image, gamePointerRva));
        lua.pushValue(L, 1);
        status = lua.pcall(L, 0, 0, 0, 0, nullptr);
    }
    lua.pushBoolean(L, status == 0);
    return 1;
}

int stepRoom(lua_State* L) {
    if (!backgroundRoom || roomScopeActive) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (++roomSteps <= 3 || roomSteps % 60 == 0) {
        log("room_poll=" + std::to_string(roomSteps) +
            " foreground_native_updates=" + std::to_string(foregroundNativeUpdates) +
            " background_native_updates=" + std::to_string(backgroundNativeUpdates) +
            " foreground_half_updates=" + std::to_string(foregroundHalfUpdates) +
            " background_half_updates=" + std::to_string(backgroundHalfUpdates));
    }
    lua.pushBoolean(L, foregroundNativeUpdates == backgroundNativeUpdates &&
                           backgroundNativeUpdates > 0);
    return 1;
}

bool bind(lua_State* L, lua::Module module) {
    using S = lua::Symbol;
    if (!lua.load(module, {S::checkInteger, S::pushBoolean, S::pushValue, S::pcall, S::pushClosure,
                           S::setField}))
        return false;
    for (const auto& [name, fn] :
         std::array<std::pair<const char*, lua::Function>, 4>{{{"create_room", createRoom},
                                                               {"with_room", withRoom},
                                                               {"step_room", stepRoom},
                                                               {"finish_rooms", finishRooms}}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace
const native_bootstrap::RoomProbe roomProbe{initialize, update, render, half, active, bind};
} // namespace isaac::engine::j510

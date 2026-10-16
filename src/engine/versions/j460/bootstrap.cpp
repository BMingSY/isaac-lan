#include "engine/bootstrap.h"
#include "engine/lua_api.h"
#include "engine/rooms.h"
#include "engine/input.h"
#include "runtime/session.h"
#include "engine/frontend.h"
#include "engine/versions/j460/entrypoints.h"
#include <MinHook.h>
#include <array>
#include <cstdio>
#include <cstring>
#include <vector>
namespace j460 = isaac::engine::j460;
namespace isaac::engine::bootstrap {
namespace {
std::uintptr_t image;
void (*log)(const std::string&);
template <class T> bool read(std::uintptr_t address, T& value) {
    SIZE_T count = 0;
    return ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(address), &value,
                             sizeof(T), &count) &&
           count == sizeof(T);
}

// RVAs belong to the J460 build, verified by layout and entry-point signatures;
// no pointer offsets from another game version are assumed to be compatible.
constexpr std::uintptr_t gamePointerRva = j460::globals::game;
constexpr std::uintptr_t roomOffset = 0x18300;
constexpr std::uintptr_t playersOffset = 0x1baa8;
constexpr std::uintptr_t frameOffset = 0x264f8;

using LuaFn = int(__cdecl*)(lua_State*);
isaac::lua::API lua{};

template <class T> T& field(std::uintptr_t base, std::size_t offset) {
    return *reinterpret_cast<T*>(base + offset);
}
template <class T> T engine(std::uintptr_t rva) {
    return reinterpret_cast<T>(image + rva);
}
using NativeRoomCall = void(__attribute__((thiscall)) *)(void*);
using NativeRoomInit = void(__attribute__((thiscall)) *)(void*, void*, void*);
using NativeGetDesc = void*(__attribute__((thiscall)) *)(void*, int, int);

std::uintptr_t backgroundRoom = 0;
int backgroundIndex = -1;
int roomSteps = 0;
bool roomScopeActive = false;
NativeRoomCall originalRoomUpdate = nullptr;
NativeRoomCall originalGameRender = nullptr;
using NativeHalfUpdate = void(__cdecl*)();
NativeHalfUpdate originalHalfUpdate = nullptr;
unsigned foregroundNativeUpdates = 0, backgroundNativeUpdates = 0;
unsigned foregroundHalfUpdates = 0, backgroundHalfUpdates = 0;
void tickBackground(std::uintptr_t game);

void __attribute__((fastcall)) updateForeground(void* room, void*) {
    if (isaac::rooms::update(room, originalRoomUpdate))
        return;
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    if (!backgroundRoom || roomScopeActive ||
        reinterpret_cast<std::uintptr_t>(room) == backgroundRoom) {
        originalRoomUpdate(room);
        return;
    }
    const auto begin = field<std::uintptr_t>(game, playersOffset);
    const auto end = field<std::uintptr_t>(game, playersOffset + 4);
    field<std::uintptr_t>(game, playersOffset + 4) = begin + 4;
    originalRoomUpdate(room);
    field<std::uintptr_t>(game, playersOffset + 4) = end;
    ++foregroundNativeUpdates;
    tickBackground(game);
}

// The eight independent EntityList backing arrays are constructed by the game.
// Remove references without destroying the entity, then let native Add register
// it in the destination's persistent, update, rendering and query structures.
void movePlayer(std::uintptr_t player, std::uintptr_t from, std::uintptr_t to) {
    for (std::size_t offset = 0x20; offset <= 0x90; offset += 0x10) {
        const auto list = from + 0x1218 + offset;
        auto data = reinterpret_cast<std::uintptr_t*>(field<std::uintptr_t>(list, 4));
        auto& size = field<unsigned>(list, 12);
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
    engine<InvalidateQuery>(j460::entry::engineRoomsInvalidate)(
        reinterpret_cast<void*>(from + 0x1218), 1, 0, 0);
    field<bool>(player, 0x170) = false;
    field<unsigned>(player, 0x20) = field<unsigned>(to, 0x1214)++;
    using Add = void(__attribute__((thiscall))*)(void*, void*);
    engine<Add>(j460::entry::engineRoomsAdd)(reinterpret_cast<void*>(to + 0x1218),
                                             reinterpret_cast<void*>(player));
}

// Internal experiment only: scoped engine view, not a complete room scheduler.
// Never copy ownership-bearing engine objects or pass MinGW STL to MSVC code.
struct RoomScope {
    std::uintptr_t game;
    std::uintptr_t originalRoom;
    int originalIndex, originalDimension;
    std::array<std::uintptr_t, 3> players;
    explicit RoomScope(std::uintptr_t g) : game(g) {
        originalRoom = field<std::uintptr_t>(g, roomOffset);
        originalIndex = field<int>(g, 0x18304);
        originalDimension = field<int>(g, 0x1830c);
        memcpy(players.data(), reinterpret_cast<void*>(g + playersOffset), sizeof(players));
        field<std::uintptr_t>(g, roomOffset) = backgroundRoom;
        field<int>(g, 0x18304) = backgroundIndex;
        field<int>(g, 0x1830c) = 0;
        // Keep the game's own backing allocation. This experiment requires two
        // ordinary players and exposes only player two during background work.
        field<std::uintptr_t>(g, playersOffset) = players[0] + 4;
        field<std::uintptr_t>(g, playersOffset + 4) = players[0] + 8;
        roomScopeActive = true;
    }
    ~RoomScope() {
        if (field<std::uintptr_t>(game, playersOffset) != players[0] + 4 ||
            field<std::uintptr_t>(game, playersOffset + 8) != players[2]) {
            log("room_scope=FAIL player_vector_reallocated");
            TerminateProcess(GetCurrentProcess(), 91);
        }
        memcpy(reinterpret_cast<void*>(game + playersOffset), players.data(), sizeof(players));
        field<std::uintptr_t>(game, roomOffset) = originalRoom;
        field<int>(game, 0x18304) = originalIndex;
        field<int>(game, 0x1830c) = originalDimension;
        roomScopeActive = false;
    }
    RoomScope(const RoomScope&) = delete;
};

void __attribute__((fastcall)) renderLocalRoom(void* game, void*) {
    isaac::input::ViewScope inputView(isaac::runtime::localViewSlot());
    isaac::runtime::present();
    isaac::frontend::prepareView();
    if (isaac::rooms::render(game, originalGameRender, isaac::runtime::localViewSlot())) {
        isaac::frontend::render();
        return;
    }
    if (backgroundRoom && !roomScopeActive && isaac::runtime::localViewSlot() == 1) {
        RoomScope context(reinterpret_cast<std::uintptr_t>(game));
        originalGameRender(game);
    } else
        originalGameRender(game);
    isaac::frontend::render();
}

void restoreRoomPositions(std::uintptr_t room) {
    // The manager restores interpolated positions only for its visible room
    // (J460 VA 0x9551d8). Apply the same operation before background physics.
    const auto list = room + 0x1218 + 0x40;
    const auto data = field<std::uintptr_t>(list, 4);
    for (unsigned i = 0; i < field<unsigned>(list, 12); ++i) {
        auto entity = field<std::uintptr_t>(data, i * 4);
        if (field<bool>(entity, 0x175)) {
            field<float>(entity, 0x33c) = field<float>(entity, 0x344);
            field<float>(entity, 0x340) = field<float>(entity, 0x348);
            field<bool>(entity, 0x175) = false;
        }
    }
}

void restoreForegroundPositions() {
    restoreRoomPositions(
        field<std::uintptr_t>(field<std::uintptr_t>(image, gamePointerRva), roomOffset));
}

void tickBackground(std::uintptr_t game) {
    RoomScope context(game);
    restoreRoomPositions(backgroundRoom);
    originalRoomUpdate(reinterpret_cast<void*>(backgroundRoom));
    ++backgroundNativeUpdates;
}

void __cdecl updateHalfFrames() {
    if (!isaac::runtime::halfAllowed())
        return;
    isaac::runtime::halfStarted();
    if (isaac::rooms::half(originalHalfUpdate)) {
        isaac::runtime::halfCompleted();
        return;
    }
    originalHalfUpdate();
    if (!backgroundRoom || roomScopeActive) {
        isaac::runtime::halfCompleted();
        return;
    }
    ++foregroundHalfUpdates;
    {
        RoomScope context(field<std::uintptr_t>(image, gamePointerRva));
        // This experiment disallows room transitions. Production needs a
        // separate transition context before this can schedule arbitrary rooms.
        originalHalfUpdate();
        ++backgroundHalfUpdates;
    }
    isaac::runtime::halfCompleted();
}

void describeRoom(const char* name, std::uintptr_t room) {
    auto list = room + 0x1218 + 0x20;
    auto data = field<std::uintptr_t>(list, 4);
    auto count = field<unsigned>(list, 12);
    char line[256];
    snprintf(line, sizeof(line), "%s room=%08lx count=%u", name, static_cast<unsigned long>(room),
             count);
    log(line);
    if (count > 2000)
        return;
    for (unsigned i = 0; i < count && i < 30; ++i) {
        auto entity = field<std::uintptr_t>(data, i * 4);
        snprintf(line, sizeof(line), " entity=%08lx type=%u variant=%u",
                 static_cast<unsigned long>(entity), field<unsigned>(entity, 0x28),
                 field<unsigned>(entity, 0x2c));
        log(line);
    }
}

int createRoom(lua_State* L) {
    const int index = static_cast<int>(lua.checkInteger(L, 1));
    auto game = field<std::uintptr_t>(image, gamePointerRva);
    if (backgroundRoom || roomScopeActive || index < 0 || index >= 169 ||
        field<int>(game, 0x18304) == index ||
        field<std::uintptr_t>(game, playersOffset + 4) -
                field<std::uintptr_t>(game, playersOffset) !=
            8) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto desc = reinterpret_cast<std::uintptr_t>(engine<NativeGetDesc>(
        j460::entry::engineRoomsDesc)(reinterpret_cast<void*>(game), index, 0));
    if (!desc || !field<std::uintptr_t>(desc, 0x10)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    log("room_create=BEGIN");
    roomSteps = 0;
    foregroundNativeUpdates = backgroundNativeUpdates = 0;
    foregroundHalfUpdates = backgroundHalfUpdates = 0;
    using Allocate = void*(__cdecl*)(std::size_t);
    backgroundRoom = reinterpret_cast<std::uintptr_t>(
        engine<Allocate>(j460::entry::engineRoomsAllocate)(0x7898));
    if (!backgroundRoom) {
        lua.pushBoolean(L, false);
        return 1;
    }
    engine<NativeRoomCall>(j460::entry::engineRoomsRoomCall_3e9400)(
        reinterpret_cast<void*>(backgroundRoom));
    backgroundIndex = index;
    {
        RoomScope context(game);
        engine<NativeRoomInit>(j460::entry::probeNativeRoomInit)(
            reinterpret_cast<void*>(backgroundRoom),
            reinterpret_cast<void*>(field<std::uintptr_t>(desc, 0x10)),
            reinterpret_cast<void*>(desc));
        auto player = field<std::uintptr_t>(field<std::uintptr_t>(game, playersOffset), 0);
        movePlayer(player, context.originalRoom, backgroundRoom);
    }
    describeRoom("foreground_after_init", field<std::uintptr_t>(game, roomOffset));
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
    auto foreground = field<std::uintptr_t>(game, roomOffset);
    auto player = field<std::uintptr_t>(field<std::uintptr_t>(game, playersOffset), 4);
    movePlayer(player, backgroundRoom, foreground);
    // Native destructor owns native container allocations; native sized delete
    // releases the object from the same allocator used during construction.
    engine<NativeRoomCall>(j460::entry::engineRoomsRoomCall_3e9ba0)(
        reinterpret_cast<void*>(backgroundRoom));
    using Delete = void(__cdecl*)(void*, std::size_t);
    engine<Delete>(j460::entry::engineRoomsDelete)(reinterpret_cast<void*>(backgroundRoom), 0x7898);
    backgroundRoom = 0;
    log("room_cleanup=RETURNED");
    lua.pushBoolean(L, true);
    return 1;
}

int traceCallback(lua_State* L) {
    const int who = static_cast<int>(lua.checkInteger(L, 1));
    static unsigned counts[3] = {};
    if (who < 1 || who > 2 || counts[who]++ >= 2)
        return 0;
    void* frames[48] = {};
    auto size = CaptureStackBackTrace(0, 48, frames, nullptr);
    std::string result = "player_callback_stack=" + std::to_string(who);
    for (unsigned i = 0; i < size; ++i) {
        auto pc = reinterpret_cast<std::uintptr_t>(frames[i]);
        if (pc >= image && pc < image + 0x92c000) {
            char address[24];
            snprintf(address, sizeof(address), " %08lx",
                     static_cast<unsigned long>(pc - image + 0x400000));
            result += address;
        }
    }
    log(result);
    return 0;
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

int audit(lua_State* L) {
    std::uintptr_t game = 0, room = 0, begin = 0, end = 0;
    int stage = 0, index = 0, gameFrame = 0, enteredFrame = 0;
    bool valid = image && read(image + gamePointerRva, game) && game &&
                 read(game + roomOffset, room) && room && read(game, stage) &&
                 read(game + 0x18304, index) && read(game + frameOffset, gameFrame) &&
                 read(room + 0x11f0, enteredFrame) && read(game + playersOffset, begin) &&
                 read(game + playersOffset + 4, end) && end >= begin && end - begin <= 32;
    int roomFrame = gameFrame - enteredFrame;
    int players = static_cast<int>((end - begin) / 4);
    if (valid)
        valid = stage == lua.checkInteger(L, 1) && index == lua.checkInteger(L, 2) &&
                roomFrame == lua.checkInteger(L, 3) && players == lua.checkInteger(L, 4);
    char line[384];
    snprintf(line, sizeof(line),
             "audit=%s game=%08lx room=%08lx stage=%d index=%d room_frame=%d players=%d",
             valid ? "PASS" : "FAIL", static_cast<unsigned long>(game),
             static_cast<unsigned long>(room), stage, index, roomFrame, players);
    log(line);
    lua.pushBoolean(L, valid);
    return 1;
}
} // namespace
int installUpdates(std::uintptr_t base, void (*logger)(const std::string&)) {
    image = base;
    log = logger;
    if (MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::roomUpdate),
                      reinterpret_cast<void*>(updateForeground),
                      reinterpret_cast<void**>(&originalRoomUpdate)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::roomUpdate)) != MH_OK)
        return 16;
    if (MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::gameUpdateHalf),
                      reinterpret_cast<void*>(updateHalfFrames),
                      reinterpret_cast<void**>(&originalHalfUpdate)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::gameUpdateHalf)) != MH_OK)
        return 17;
    return 0;
}
int installRendering() {
    if (MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::gameRender),
                      reinterpret_cast<void*>(renderLocalRoom),
                      reinterpret_cast<void**>(&originalGameRender)) != MH_OK ||
        MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::gameRender)) != MH_OK)
        return 20;
    return 0;
}
void halfUpdate() {
    updateHalfFrames();
}
void restorePositions() {
    restoreForegroundPositions();
}
bool scopeActive() {
    return roomScopeActive;
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module,
                  {lua::Symbol::createTable, lua::Symbol::pushClosure, lua::Symbol::setField,
                   lua::Symbol::pushString, lua::Symbol::checkInteger, lua::Symbol::checkString,
                   lua::Symbol::checkNumber, lua::Symbol::pushBoolean, lua::Symbol::pushValue,
                   lua::Symbol::pcall}))
        return false;
    for (const auto& [name, fn] : std::array<std::pair<const char*, lua::Function>, 6>{
             {{"audit", audit},
              {"create_room", createRoom},
              {"with_room", withRoom},
              {"step_room", stepRoom},
              {"finish_rooms", finishRooms},
              {"trace_callback", traceCallback}}}) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace isaac::engine::bootstrap

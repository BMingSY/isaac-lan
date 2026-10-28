#pragma once
#include "engine/lua_api.h"
#include "engine/versions/common/room_hooks.h"
#include <cstdint>
#include <string>

namespace isaac::engine::native_bootstrap {
using Address = std::uintptr_t;
using Logger = void (*)(const std::string&);
using HalfUpdate = void (*)();
// Optional diagnostic experiment. Original calls and objects are borrowed only
// during each callback; the production room scheduler always gets priority.
struct RoomProbe {
    void (*initialize)(Address, Logger);
    bool (*update)(void*, rooms::RoomCall);
    bool (*render)(void*, rooms::RoomCall, int);
    void (*half)(HalfUpdate);
    bool (*active)();
    bool (*bind)(lua_State*, lua::Module);
};
struct Bindings {
    struct Entries {
        unsigned roomUpdate, gameUpdateHalf, gameRender;
    } entry;
    unsigned game, preferredImageBase, diagnosticImageSpan;
    struct Layout {
        struct Game {
            unsigned room, roomIndex, players, frame;
        } game;
        struct Room {
            unsigned entities, enteredFrame;
        } room;
        struct EntityList {
            unsigned renderArray, data, count;
        } entityList;
        struct Entity {
            unsigned interpolated, positionX, positionY, previousX, previousY;
        } entity;
        struct Vector {
            unsigned end;
        } vector;
    } layout;
    const RoomProbe* probe;
};
extern const Bindings bindings;
void restoreRoomPositions(Address room);
} // namespace isaac::engine::native_bootstrap

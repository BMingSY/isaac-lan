#pragma once
#include "engine/versions/common/rails.h"
namespace isaac::engine::native_grid {
inline constexpr unsigned doorSlots = 8, doorType = 16;
struct Bindings {
    unsigned gameGlobal, gameRoom, removeImmediate, makeDoor;
    struct Room {
        unsigned cells, doors, indices;
    } room;
    struct Grid {
        unsigned sprite, extraSprite, type, variant, index;
    } grid;
    native_rails::Layout rails;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_grid

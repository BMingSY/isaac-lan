#pragma once
#include <cstddef>
#include <cstdint>

namespace isaac::engine::native_room_routing {
// Private native boundaries, after Maze containers have been destroyed and
// EnterDoor resolved, before destination initialization. Both versions keep an
// EBP frame and have a common SEH epilogue that releases two stack arguments.
struct Bindings {
    struct Entries {
        std::uint32_t resolved, roomReturn, maze, mazeEnd, addedCurses, removedCurses;
    } entry;
    std::uint32_t game;
    struct Layout {
        unsigned roomIndex, dimension, enterDoor, curses, seedCurses;
        std::ptrdiff_t redirected;
    } layout;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_room_routing

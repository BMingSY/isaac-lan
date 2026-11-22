#include "engine/versions/common/room_routing_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_room_routing {
const Bindings bindings{
    .entry = {j511::entry::levelRoomEntryResolved, j511::entry::levelRoomChangeReturn,
              j511::entry::levelMazeBranch, j511::entry::levelMazeBranchEnd,
              j511::entry::gameAddedSeedCurses, j511::entry::gameRemovedSeedCurses, std::nullopt},
    .game = j511::globals::game,
    .layout = {j511::layout::game::roomIndex, j511::layout::game::dimension,
               j511::layout::game::enterDoor, j511::layout::game::curses,
               j511::layout::game::seedCurses, j511::layout::roomChangeFrame::mazeRedirected}};
} // namespace isaac::engine::native_room_routing

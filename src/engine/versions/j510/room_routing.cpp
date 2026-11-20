#include "engine/versions/common/room_routing_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_room_routing {
const Bindings bindings{
    .entry = {j510::entry::levelRoomEntryResolved, j510::entry::levelRoomChangeReturn,
              j510::entry::levelMazeBranch, j510::entry::levelMazeBranchEnd,
              j510::entry::gameAddedSeedCurses, j510::entry::gameRemovedSeedCurses, std::nullopt},
    .game = j510::globals::game,
    .layout = {j510::layout::game::roomIndex, j510::layout::game::dimension,
               j510::layout::game::enterDoor, j510::layout::game::curses,
               j510::layout::game::seedCurses, j510::layout::roomChangeFrame::mazeRedirected}};
} // namespace isaac::engine::native_room_routing

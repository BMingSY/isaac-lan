#include "engine/versions/common/room_routing_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_room_routing {
const Bindings bindings{
    .entry = {j835::entry::levelRoomEntryResolved, j835::entry::levelRoomChangeReturn,
              j835::entry::levelMazeBranch, j835::entry::levelMazeBranchEnd,
              j835::entry::gameAddedSeedCurses, j835::entry::gameRemovedSeedCurses,
              j835::entry::roomPrepareRenderImages},
    .game = j835::globals::game,
    .layout = {j835::layout::game::roomIndex, j835::layout::game::dimension,
               j835::layout::game::enterDoor, j835::layout::game::curses,
               j835::layout::game::seedCurses, j835::layout::roomChangeFrame::mazeRedirected}};
} // namespace isaac::engine::native_room_routing

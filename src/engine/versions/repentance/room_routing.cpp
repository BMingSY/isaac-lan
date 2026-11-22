#include "engine/versions/common/room_routing_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_room_routing {
const Bindings bindings{
    .entry = {repentance::entry::levelRoomEntryResolved, repentance::entry::levelRoomChangeReturn,
              repentance::entry::levelMazeBranch, repentance::entry::levelMazeBranchEnd,
              repentance::entry::gameAddedSeedCurses, repentance::entry::gameRemovedSeedCurses,
              repentance::entry::roomPrepareRenderImages},
    .game = repentance::globals::game,
    .layout = {repentance::layout::game::roomIndex, repentance::layout::game::dimension,
               repentance::layout::game::enterDoor, repentance::layout::game::curses,
               repentance::layout::game::seedCurses,
               repentance::layout::roomChangeFrame::mazeRedirected}};
} // namespace isaac::engine::native_room_routing

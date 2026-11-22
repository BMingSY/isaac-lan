#include "engine/versions/common/room_routing_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_room_routing {
const Bindings bindings{
    .entry = {repentance_plus::entry::levelRoomEntryResolved,
              repentance_plus::entry::levelRoomChangeReturn,
              repentance_plus::entry::levelMazeBranch, repentance_plus::entry::levelMazeBranchEnd,
              repentance_plus::entry::gameAddedSeedCurses,
              repentance_plus::entry::gameRemovedSeedCurses, std::nullopt},
    .game = repentance_plus::globals::game,
    .layout = {repentance_plus::layout::game::roomIndex, repentance_plus::layout::game::dimension,
               repentance_plus::layout::game::enterDoor, repentance_plus::layout::game::curses,
               repentance_plus::layout::game::seedCurses,
               repentance_plus::layout::roomChangeFrame::mazeRedirected}};
} // namespace isaac::engine::native_room_routing

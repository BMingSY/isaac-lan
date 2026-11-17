#include "engine/versions/common/room_routing_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_room_routing {
const Bindings bindings{
    .entry = {j460::entry::levelRoomEntryResolved, j460::entry::levelRoomChangeReturn,
              j460::entry::levelMazeBranch, j460::entry::levelMazeBranchEnd,
              j460::entry::gameAddedSeedCurses, j460::entry::gameRemovedSeedCurses, std::nullopt},
    .game = j460::globals::game,
    .layout = {j460::layout::game::roomIndex, j460::layout::game::dimension,
               j460::layout::game::enterDoor, j460::layout::game::curses,
               j460::layout::game::seedCurses, j460::layout::roomChangeFrame::mazeRedirected}};
} // namespace isaac::engine::native_room_routing

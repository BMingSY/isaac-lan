#include "engine/versions/common/player_input.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_players {
const Bindings bindings{j511::globals::game,
                        j511::entry::engineInputSpawn,
                        j511::entry::engineRoomsAssign,
                        j511::entry::engineInputInitialize,
                        j511::entry::engineRoomsGetHUD,
                        j511::entry::engineRoomsRoomCall_5a8620,
                        j511::layout::game::playerManager,
                        j511::layout::game::players,
                        j511::layout::player::controller,
                        j511::layout::entity::positionX,
                        j511::layout::entity::positionY,
                        j511::layout::entity::previousX,
                        j511::layout::entity::previousY};
} // namespace isaac::engine::native_players

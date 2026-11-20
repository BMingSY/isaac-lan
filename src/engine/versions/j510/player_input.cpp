#include "engine/versions/common/player_input.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_players {
const Bindings bindings{j510::globals::game,
                        j510::entry::engineInputSpawn,
                        j510::entry::engineRoomsAssign,
                        j510::entry::engineInputInitialize,
                        j510::entry::engineRoomsGetHUD,
                        j510::entry::engineRoomsRoomCall_5a8620,
                        j510::layout::game::playerManager,
                        j510::layout::game::players,
                        j510::layout::player::controller,
                        j510::layout::entity::positionX,
                        j510::layout::entity::positionY,
                        j510::layout::entity::previousX,
                        j510::layout::entity::previousY};
} // namespace isaac::engine::native_players

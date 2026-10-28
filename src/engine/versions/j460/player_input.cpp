#include "engine/versions/common/player_input.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_players {
const Bindings bindings{j460::globals::game,
                        j460::entry::engineInputSpawn,
                        j460::entry::engineRoomsAssign,
                        j460::entry::engineInputInitialize,
                        j460::entry::engineRoomsGetHUD,
                        j460::entry::engineRoomsRoomCall_5a8620,
                        j460::layout::game::playerManager,
                        j460::layout::game::players,
                        j460::layout::player::controller,
                        j460::layout::entity::positionX,
                        j460::layout::entity::positionY,
                        j460::layout::entity::previousX,
                        j460::layout::entity::previousY};
} // namespace isaac::engine::native_players

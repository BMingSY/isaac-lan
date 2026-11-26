#include "engine/versions/common/player_input.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_players {
const Bindings bindings{repentance_plus::globals::game,
                        repentance_plus::entry::engineInputSpawn,
                        repentance_plus::entry::engineRoomsAssign,
                        repentance_plus::entry::engineInputInitialize,
                        repentance_plus::entry::engineRoomsGetHUD,
                        repentance_plus::entry::engineRoomsRoomCall_5a8620,
                        repentance_plus::layout::game::playerManager,
                        repentance_plus::layout::game::players,
                        repentance_plus::layout::player::controller,
                        repentance_plus::layout::entity::positionX,
                        repentance_plus::layout::entity::positionY,
                        repentance_plus::layout::entity::previousX,
                        repentance_plus::layout::entity::previousY,
                        repentance_plus::layout::entity::initSeed,
                        repentance_plus::layout::entity::parent,
                        repentance_plus::layout::player::twin,
                        repentance_plus::layout::player::lazarusBackup};
} // namespace isaac::engine::native_players

#include "engine/versions/common/player_input.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_players {
const Bindings bindings{repentance::globals::game,
                        repentance::entry::playerManagerSpawn,
                        repentance::entry::playerAssignController,
                        repentance::entry::playerInitialize,
                        repentance::entry::gameGetHUD,
                        repentance::entry::hudAssignPlayers,
                        repentance::layout::game::playerManager,
                        repentance::layout::game::players,
                        repentance::layout::player::controller,
                        repentance::layout::entity::positionX,
                        repentance::layout::entity::positionY,
                        repentance::layout::entity::previousX,
                        repentance::layout::entity::previousY};
} // namespace isaac::engine::native_players

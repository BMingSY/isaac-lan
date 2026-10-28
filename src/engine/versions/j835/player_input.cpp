#include "engine/versions/common/player_input.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_players {
const Bindings bindings{j835::globals::game,
                        j835::entry::playerManagerSpawn,
                        j835::entry::playerAssignController,
                        j835::entry::playerInitialize,
                        j835::entry::gameGetHUD,
                        j835::entry::hudAssignPlayers,
                        j835::layout::game::playerManager,
                        j835::layout::game::players,
                        j835::layout::player::controller,
                        j835::layout::entity::positionX,
                        j835::layout::entity::positionY,
                        j835::layout::entity::previousX,
                        j835::layout::entity::previousY};
} // namespace isaac::engine::native_players

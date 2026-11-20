#include "engine/versions/common/frontend_hud_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
namespace isaac::engine::native_frontend_hud {
namespace backend = j835;
namespace layout = backend::layout;
const Bindings bindings{
    backend::globals::game,
    layout::game::players,
    layout::hud::history,
    {backend::entry::frontendStatHUDGetPlayerId, backend::entry::frontendStatHUDReset,
     backend::entry::historyHUDGetPlayerId, backend::entry::historyHUDRecomputeAll,
     backend::entry::playerHUDReset, backend::entry::hUDUpdate, backend::entry::hUDPostUpdate,
     backend::entry::hUDRender},
    {layout::statHud::player, layout::statHud::cacheStride, layout::statHud::cacheCount},
    {layout::player::controller, layout::player::index, layout::player::twin, layout::player::type},
    {layout::entity::parent, layout::entity::active},
    {layout::playerHud::size, layout::playerHud::refreshFlags, layout::playerHud::refreshAll}};
} // namespace isaac::engine::native_frontend_hud

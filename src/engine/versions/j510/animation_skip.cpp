#include "engine/versions/common/animation_skip_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"
#include "engine/versions/j510/menu_state.h"

namespace isaac::engine::native_animation {
namespace layout = j510::layout;
constinit const Bindings bindings{
    {j510::entry::nightmareSceneRender, j510::entry::nightmareSceneUpdate,
     j510::entry::nightmareSceneShow},
    j510::globals::game,
    j510::globals::manager,
    {layout::manager::scene, layout::manager::nightmare, layout::nightmare::active,
     layout::nightmare::home, layout::game::stageTransition},
    j510::scene::game,
    layout::nightmare::scene,
};
} // namespace isaac::engine::native_animation

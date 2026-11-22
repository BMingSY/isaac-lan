#include "engine/versions/common/animation_skip_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
#include "engine/versions/j511/menu_state.h"

namespace isaac::engine::native_animation {
namespace layout = j511::layout;
constinit const Bindings bindings{
    {j511::entry::nightmareSceneRender, j511::entry::nightmareSceneUpdate,
     j511::entry::nightmareSceneShow},
    j511::globals::game,
    j511::globals::manager,
    {layout::manager::scene, layout::manager::nightmare, layout::nightmare::active,
     layout::nightmare::home, layout::game::stageTransition},
    j511::scene::game,
    layout::nightmare::scene,
};
} // namespace isaac::engine::native_animation

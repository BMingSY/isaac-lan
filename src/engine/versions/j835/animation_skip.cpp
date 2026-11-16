#include "engine/versions/common/animation_skip_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include "engine/versions/j835/menu_state.h"

namespace isaac::engine::native_animation {
namespace layout = j835::layout;
constinit const Bindings bindings{
    {j835::entry::nightmareSceneRender, j835::entry::nightmareSceneUpdate,
     j835::entry::nightmareSceneShow},
    j835::globals::game,
    j835::globals::manager,
    {layout::manager::scene, layout::manager::nightmare, layout::nightmare::active,
     layout::nightmare::home, layout::game::stageTransition},
    j835::scene::game,
    layout::nightmare::scene,
};
} // namespace isaac::engine::native_animation

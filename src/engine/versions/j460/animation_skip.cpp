#include "engine/versions/common/animation_skip_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"

namespace isaac::engine::native_animation {
namespace layout = j460::layout;
constinit const Bindings bindings{
    {j460::entry::nightmareSceneRender, j460::entry::nightmareSceneUpdate,
     j460::entry::nightmareSceneShow},
    j460::globals::game,
    j460::globals::manager,
    {layout::manager::scene, layout::manager::nightmare, layout::nightmare::active,
     layout::nightmare::home, layout::game::stageTransition},
    j460::scene::game,
    layout::nightmare::scene,
};
} // namespace isaac::engine::native_animation

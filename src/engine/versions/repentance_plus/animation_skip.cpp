#include "engine/versions/common/animation_skip_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/menu_state.h"

namespace isaac::engine::native_animation {
namespace layout = repentance_plus::layout;
constinit const Bindings bindings{
    {repentance_plus::entry::nightmareSceneRender, repentance_plus::entry::nightmareSceneUpdate,
     repentance_plus::entry::nightmareSceneShow},
    repentance_plus::globals::game,
    repentance_plus::globals::manager,
    {layout::manager::scene, layout::manager::nightmare, layout::nightmare::active,
     layout::nightmare::home, layout::game::stageTransition},
    repentance_plus::scene::game,
    layout::nightmare::scene,
};
} // namespace isaac::engine::native_animation

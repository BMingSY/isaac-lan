#include "engine/versions/common/animation_skip_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/menu_state.h"

namespace isaac::engine::native_animation {
namespace layout = repentance::layout;
constinit const Bindings bindings{
    {repentance::entry::nightmareSceneRender, repentance::entry::nightmareSceneUpdate,
     repentance::entry::nightmareSceneShow},
    repentance::globals::game,
    repentance::globals::manager,
    {layout::manager::scene, layout::manager::nightmare, layout::nightmare::active,
     layout::nightmare::home, layout::game::stageTransition},
    repentance::scene::game,
    layout::nightmare::scene,
};
} // namespace isaac::engine::native_animation

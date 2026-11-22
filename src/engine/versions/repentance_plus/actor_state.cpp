#include "engine/versions/common/actor_state_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
namespace isaac::engine::native_actor_state {
namespace backend = repentance_plus;
namespace layout = backend::layout;
const Bindings bindings{backend::globals::game,
                        backend::entry::engineRoomsGetHUD,
                        {layout::entity::sprite, layout::entity::type},
                        {layout::player::type, layout::player::costumesBegin,
                         layout::costume::stride, layout::player::chargeSprites,
                         layout::sprite::size, layout::player::syncSprites, layout::player::pockets,
                         layout::player::bagMaterials, layout::player::bagPreview,
                         layout::player::poopMana, layout::player::poopQueue},
                        {layout::playerHud::size, layout::playerHud::bagDirty}};
} // namespace isaac::engine::native_actor_state

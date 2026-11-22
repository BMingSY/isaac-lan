#include "engine/versions/common/entity_pose_bindings.h"
#include "engine/versions/j511/layout.h"
namespace isaac::engine::native_entity_pose {
namespace layout = j511::layout;
const Bindings bindings{
    {layout::entity::sprite, layout::entity::type, layout::entity::shadow},
    {layout::player::poseFlags, layout::player::blinkTime, layout::player::damageCooldown,
     layout::player::nightLightAngle, layout::player::weapons, layout::player::costumesBegin,
     layout::player::costumesEnd, layout::costume::stride, layout::costume::path,
     layout::player::costumeLayers, layout::costume::layerStride, layout::costume::index,
     layout::costume::layerId, layout::costume::priority, layout::costume::body},
    {layout::weapon::kind, layout::weapon::modifiers, layout::weapon::maxChargeMethod,
     layout::weapon::charge}};
} // namespace isaac::engine::native_entity_pose

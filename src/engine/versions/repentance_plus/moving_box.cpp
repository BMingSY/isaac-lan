#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_moving_box {
namespace layout = repentance_plus::layout;
constinit const Bindings bindings{
    repentance_plus::entry::movingBoxHudBranch,
    repentance_plus::entry::movingBoxHudFull,
    repentance_plus::entry::movingBoxHudEmpty,
    native_branch::ecx,
    layout::entity::initSeed,
    layout::player::movingBoxBegin,
    layout::player::movingBoxEnd,
};
} // namespace isaac::engine::native_moving_box

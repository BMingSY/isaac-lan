#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_moving_box {
namespace layout = repentance::layout;
constinit const Bindings bindings{
    repentance::entry::movingBoxHudBranch,
    repentance::entry::movingBoxHudFull,
    repentance::entry::movingBoxHudEmpty,
    native_branch::edi,
    layout::entity::initSeed,
    layout::player::movingBoxBegin,
    layout::player::movingBoxEnd,
};
} // namespace isaac::engine::native_moving_box

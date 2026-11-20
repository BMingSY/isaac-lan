#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_moving_box {
namespace layout = j510::layout;
constinit const Bindings bindings{
    j510::entry::movingBoxHudBranch, j510::entry::movingBoxHudFull,
    j510::entry::movingBoxHudEmpty,  native_branch::ecx,
    layout::entity::initSeed,        layout::player::movingBoxBegin,
    layout::player::movingBoxEnd,
};
} // namespace isaac::engine::native_moving_box

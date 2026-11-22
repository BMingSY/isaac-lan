#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_moving_box {
namespace layout = j511::layout;
constinit const Bindings bindings{
    j511::entry::movingBoxHudBranch, j511::entry::movingBoxHudFull,
    j511::entry::movingBoxHudEmpty,  native_branch::ecx,
    layout::entity::initSeed,        layout::player::movingBoxBegin,
    layout::player::movingBoxEnd,
};
} // namespace isaac::engine::native_moving_box

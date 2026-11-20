#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_moving_box {
namespace layout = j835::layout;
constinit const Bindings bindings{
    j835::entry::movingBoxHudBranch, j835::entry::movingBoxHudFull,
    j835::entry::movingBoxHudEmpty,  native_branch::edi,
    layout::entity::initSeed,        layout::player::movingBoxBegin,
    layout::player::movingBoxEnd,
};
} // namespace isaac::engine::native_moving_box

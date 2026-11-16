#include "engine/versions/common/moving_box_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_moving_box {
namespace layout = j460::layout;
constinit const Bindings bindings{
    j460::entry::movingBoxHudBranch, j460::entry::movingBoxHudFull,
    j460::entry::movingBoxHudEmpty,  native_branch::ecx,
    layout::entity::initSeed,        layout::player::movingBoxBegin,
    layout::player::movingBoxEnd,
};
} // namespace isaac::engine::native_moving_box

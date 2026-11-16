#pragma once
#include "engine/versions/common/branch_frame.h"

namespace isaac::engine::native_moving_box {
struct Bindings {
    unsigned branch, full, empty;
    native_branch::Register player;
    unsigned initSeed, begin, end;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_moving_box

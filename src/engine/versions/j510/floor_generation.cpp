#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/j510/entrypoints.h"

namespace isaac::engine::native_floor_generation {
constinit const Bindings bindings{j510::entry::levelLargeFloorCount,
                                  j510::entry::levelLargeFloorShape};
} // namespace isaac::engine::native_floor_generation

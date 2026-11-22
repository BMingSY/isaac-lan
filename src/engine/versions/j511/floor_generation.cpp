#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/j511/entrypoints.h"

namespace isaac::engine::native_floor_generation {
constinit const Bindings bindings{j511::entry::levelLargeFloorCount,
                                  j511::entry::levelLargeFloorShape};
} // namespace isaac::engine::native_floor_generation

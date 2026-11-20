#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/j835/entrypoints.h"

namespace isaac::engine::native_floor_generation {
constinit const Bindings bindings{j835::entry::levelLargeFloorCount,
                                  j835::entry::levelLargeFloorShape};
} // namespace isaac::engine::native_floor_generation

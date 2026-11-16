#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/j460/entrypoints.h"

namespace isaac::engine::native_floor_generation {
constinit const Bindings bindings{j460::entry::levelLargeFloorCount,
                                  j460::entry::levelLargeFloorShape};
} // namespace isaac::engine::native_floor_generation

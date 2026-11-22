#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/repentance/entrypoints.h"

namespace isaac::engine::native_floor_generation {
constinit const Bindings bindings{repentance::entry::levelLargeFloorCount,
                                  repentance::entry::levelLargeFloorShape};
} // namespace isaac::engine::native_floor_generation

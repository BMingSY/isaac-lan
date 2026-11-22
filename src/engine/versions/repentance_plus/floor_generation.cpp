#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"

namespace isaac::engine::native_floor_generation {
constinit const Bindings bindings{repentance_plus::entry::levelLargeFloorCount,
                                  repentance_plus::entry::levelLargeFloorShape};
} // namespace isaac::engine::native_floor_generation

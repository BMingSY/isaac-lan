#include "engine/versions/common/laser_state_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
namespace isaac::engine::native_laser_state {
namespace backend = repentance_plus;
namespace layout = backend::layout;
const Bindings bindings{backend::entry::engineRoomsAllocate,
                        backend::entry::engineRoomsDelete,
                        layout::entity::sprite,
                        layout::entity::type,
                        layout::laser::sampleState,
                        layout::laser::samples,
                        layout::laser::values,
                        layout::laser::paths};
} // namespace isaac::engine::native_laser_state

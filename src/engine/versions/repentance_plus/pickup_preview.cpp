#include "engine/versions/common/pickup_preview_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_pickup_preview {
const Bindings bindings{repentance_plus::entry::pickupUpdateGhosts,
                        repentance_plus::globals::game,
                        repentance_plus::layout::game::room,
                        repentance_plus::layout::room::entities,
                        repentance_plus::layout::entityList::renderArray,
                        repentance_plus::layout::entityList::data,
                        repentance_plus::layout::entityList::count,
                        repentance_plus::layout::entity::type};
} // namespace isaac::engine::native_pickup_preview

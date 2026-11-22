#include "engine/versions/common/pickup_preview_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_pickup_preview {
const Bindings bindings{repentance::entry::pickupUpdateGhosts,
                        repentance::globals::game,
                        repentance::layout::game::room,
                        repentance::layout::room::entities,
                        repentance::layout::entityList::renderArray,
                        repentance::layout::entityList::data,
                        repentance::layout::entityList::count,
                        repentance::layout::entity::type};
} // namespace isaac::engine::native_pickup_preview

#include "engine/versions/common/pickup_preview_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_pickup_preview {
const Bindings bindings{j511::entry::pickupUpdateGhosts,
                        j511::globals::game,
                        j511::layout::game::room,
                        j511::layout::room::entities,
                        j511::layout::entityList::renderArray,
                        j511::layout::entityList::data,
                        j511::layout::entityList::count,
                        j511::layout::entity::type};
} // namespace isaac::engine::native_pickup_preview

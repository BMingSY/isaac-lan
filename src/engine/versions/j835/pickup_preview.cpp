#include "engine/versions/common/pickup_preview_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_pickup_preview {
const Bindings bindings{j835::entry::pickupUpdateGhosts,
                        j835::globals::game,
                        j835::layout::game::room,
                        j835::layout::room::entities,
                        j835::layout::entityList::renderArray,
                        j835::layout::entityList::data,
                        j835::layout::entityList::count,
                        j835::layout::entity::type};
} // namespace isaac::engine::native_pickup_preview

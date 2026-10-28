#include "engine/versions/common/pickup_preview_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_pickup_preview {
const Bindings bindings{j460::entry::pickupUpdateGhosts,
                        j460::globals::game,
                        j460::layout::game::room,
                        j460::layout::room::entities,
                        j460::layout::entityList::renderArray,
                        j460::layout::entityList::data,
                        j460::layout::entityList::count,
                        j460::layout::entity::type};
} // namespace isaac::engine::native_pickup_preview

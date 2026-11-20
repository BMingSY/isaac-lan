#include "engine/versions/common/pickup_preview_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_pickup_preview {
const Bindings bindings{j510::entry::pickupUpdateGhosts,
                        j510::globals::game,
                        j510::layout::game::room,
                        j510::layout::room::entities,
                        j510::layout::entityList::renderArray,
                        j510::layout::entityList::data,
                        j510::layout::entityList::count,
                        j510::layout::entity::type};
} // namespace isaac::engine::native_pickup_preview

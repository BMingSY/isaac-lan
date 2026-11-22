#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/j511/entrypoints.h"

namespace isaac::engine::native_room_queries {
const Bindings bindings{j511::entry::playerManagerFindPlayerType, true};
} // namespace isaac::engine::native_room_queries

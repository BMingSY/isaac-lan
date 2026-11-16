#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/j460/entrypoints.h"

namespace isaac::engine::native_room_queries {
const Bindings bindings{j460::entry::playerManagerFindPlayerType, true};
} // namespace isaac::engine::native_room_queries

#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/j510/entrypoints.h"

namespace isaac::engine::native_room_queries {
const Bindings bindings{j510::entry::playerManagerFindPlayerType, true};
} // namespace isaac::engine::native_room_queries

#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"

namespace isaac::engine::native_room_queries {
const Bindings bindings{repentance_plus::entry::playerManagerFindPlayerType, true};
} // namespace isaac::engine::native_room_queries

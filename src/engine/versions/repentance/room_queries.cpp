#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/repentance/entrypoints.h"

namespace isaac::engine::native_room_queries {
const Bindings bindings{repentance::entry::playerManagerHasPlayerType, false};
} // namespace isaac::engine::native_room_queries

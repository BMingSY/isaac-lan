#include "engine/versions/common/room_query_bindings.h"
#include "engine/versions/j835/entrypoints.h"

namespace isaac::engine::native_room_queries {
const Bindings bindings{j835::entry::playerManagerHasPlayerType, false};
} // namespace isaac::engine::native_room_queries

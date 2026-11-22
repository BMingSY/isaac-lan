#include "engine/versions/common/scene_update_bindings.h"
#include "engine/versions/repentance/entrypoints.h"

namespace isaac::engine::native_scene_update {
// Game::Update inlines the entire boss overlay update between these points.
// Skip its animation markers and route writes together, retaining every live
// register and the original EDI Game receiver at the following update block.
const Bindings bindings{repentance::entry::bossOverlayUpdateBoundary,
                        repentance::entry::bossOverlayUpdateSkip};
} // namespace isaac::engine::native_scene_update

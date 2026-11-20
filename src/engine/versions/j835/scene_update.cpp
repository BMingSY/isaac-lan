#include "engine/versions/common/scene_update_bindings.h"
#include "engine/versions/j835/entrypoints.h"

namespace isaac::engine::native_scene_update {
// Game::Update inlines the entire boss overlay update between these points.
// Skip its animation markers and route writes together, retaining every live
// register and the original EDI Game receiver at the following update block.
const Bindings bindings{j835::entry::bossOverlayUpdateBoundary, j835::entry::bossOverlayUpdateSkip};
} // namespace isaac::engine::native_scene_update

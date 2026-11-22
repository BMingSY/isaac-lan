#include "engine/versions/common/scene_update_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"

namespace isaac::engine::native_scene_update {
const Bindings bindings{repentance_plus::entry::bossOverlayUpdate, std::nullopt};
} // namespace isaac::engine::native_scene_update

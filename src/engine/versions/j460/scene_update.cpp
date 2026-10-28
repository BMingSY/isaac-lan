#include "engine/versions/common/scene_update_bindings.h"
#include "engine/versions/j460/entrypoints.h"

namespace isaac::engine::native_scene_update {
const Bindings bindings{j460::entry::bossOverlayUpdate, std::nullopt};
} // namespace isaac::engine::native_scene_update

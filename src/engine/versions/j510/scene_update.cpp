#include "engine/versions/common/scene_update_bindings.h"
#include "engine/versions/j510/entrypoints.h"

namespace isaac::engine::native_scene_update {
const Bindings bindings{j510::entry::bossOverlayUpdate, std::nullopt};
} // namespace isaac::engine::native_scene_update

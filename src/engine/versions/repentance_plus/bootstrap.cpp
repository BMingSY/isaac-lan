#include "engine/bootstrap.h"
#include "engine/versions/common/bootstrap_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/profile.h"
#include "engine/versions/repentance_plus/room_probe.h"
namespace isaac::engine::native_bootstrap {
namespace backend = repentance_plus;
namespace layout = backend::layout;
const Bindings bindings{
    {backend::entry::roomUpdate, backend::entry::gameUpdateHalf, backend::entry::gameRender},
    backend::globals::game,
    backend::preferredImageBase,
    backend::diagnosticImageSpan,
    {{layout::game::room, layout::game::roomIndex, layout::game::players, layout::game::frame},
     {layout::room::entities, layout::room::enteredFrame},
     {layout::entityList::renderArray, layout::entityList::data, layout::entityList::count},
     {layout::entity::interpolated, layout::entity::positionX, layout::entity::positionY,
      layout::entity::previousX, layout::entity::previousY},
     {layout::vector::end}},
    &backend::roomProbe};
} // namespace isaac::engine::native_bootstrap

namespace isaac::engine::bootstrap {
HookTiming scheduleGameHooks(std::uintptr_t, const std::filesystem::path&, void (*)()) {
    return HookTiming::immediate;
}
} // namespace isaac::engine::bootstrap

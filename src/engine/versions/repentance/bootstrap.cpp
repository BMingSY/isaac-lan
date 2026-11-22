#include "engine/versions/common/bootstrap_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/profile.h"
namespace isaac::engine::native_bootstrap {
namespace backend = repentance;
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
    nullptr};
} // namespace isaac::engine::native_bootstrap

#include "engine/versions/common/grid_state_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
namespace isaac::engine::native_grid {
namespace backend = repentance_plus;
namespace layout = backend::layout;
const Bindings bindings{
    backend::globals::game,
    layout::game::room,
    backend::entry::roomRemoveGridEntityImmediate,
    backend::entry::roomMakeDoor,
    {layout::room::gridCells, layout::room::doors, layout::room::doorIndices},
    {layout::grid::sprite, layout::grid::extraSprite, layout::grid::type, layout::grid::variant,
     layout::grid::index},
    {layout::room::railGrid, layout::room::railOwner, layout::room::width, layout::room::height}};
} // namespace isaac::engine::native_grid

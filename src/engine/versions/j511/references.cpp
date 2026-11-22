#include "engine/versions/common/references_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
namespace isaac::engine::native_references {
namespace backend = j511;
namespace layout = backend::layout;
const Bindings bindings{layout::entity::sprite,
                        backend::entry::entityPtrAssign,
                        backend::entry::bossHeldBombsResize,
                        {layout::entity::type, layout::entity::index, layout::entity::minecart,
                         layout::player::heldEntity},
                        {layout::entity::type, layout::entity::index, layout::heldBombs::container,
                         layout::heldBombs::map, layout::heldBombs::capacity,
                         layout::heldBombs::first, layout::heldBombs::count,
                         layout::heldBombs::blockElements}};
} // namespace isaac::engine::native_references

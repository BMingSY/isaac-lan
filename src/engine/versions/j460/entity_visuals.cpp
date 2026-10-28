#include "engine/versions/common/entity_visuals_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
namespace isaac::engine::native_visuals {
namespace backend = j460;
namespace layout = backend::layout;
const Bindings bindings{
    layout::entity::type,
    layout::entity::sprite,
    layout::sprite::size,
    layout::familiar::extraData,
    backend::entry::nPCNeedlePrepareVisual,
    backend::entry::familiarRenderTether,
    {layout::familiarBody::dataVtable, layout::familiarBody::sprites, layout::familiarBody::layers},
    {layout::tether::dataVtable, layout::tether::points, layout::tether::capacity,
     layout::tether::first, layout::tether::count, layout::tether::sprite, layout::tether::size}};
} // namespace isaac::engine::native_visuals

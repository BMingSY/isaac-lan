#include <windows.h>
#include "engine/versions/common/combat_feedback_bindings.h"
#include "engine/versions/j835/entity_cast.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_combat_feedback {
namespace layout = j835::layout;
static_assert(layout::color::size == colorBytes);
// The audited damage SetColor call owns ESI=queue record; the queue-clear
// boundary owns EDI=entity. Both versions share these private hook thunks.
const Bindings bindings{
    j835::entry::npcTakeDamage,
    j835::entry::entitySetColor,
    j835::entry::entityDamageColorReturn,
    j835::entry::entityDamageDrain,
    j835::globals::game,
    {layout::entity::type, layout::entity::initSeed, layout::entity::index, layout::entity::sprite,
     layout::entity::sprite + layout::sprite::color, layout::entity::damageQueue,
     layout::entity::damageRecordSize, layout::entity::active},
    {layout::game::dimension, layout::game::roomIndex, layout::room::entities,
     layout::entityList::renderArray, layout::entityList::data, layout::entityList::count},
    layout::entityRef::entity,
    j835::entity_cast::npc};
} // namespace isaac::engine::native_combat_feedback

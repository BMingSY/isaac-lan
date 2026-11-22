#include <windows.h>
#include "engine/versions/common/combat_feedback_bindings.h"
#include "engine/versions/j511/entity_cast.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"

namespace isaac::engine::native_combat_feedback {
namespace layout = j511::layout;
static_assert(layout::color::size == colorBytes);
// The audited damage SetColor call owns ESI=queue record; the queue-clear
// boundary owns EDI=entity. Both versions share these private hook thunks.
const Bindings bindings{
    j511::entry::npcTakeDamage,
    j511::entry::entitySetColor,
    j511::entry::entityDamageColorReturn,
    j511::entry::entityDamageDrain,
    j511::globals::game,
    {layout::entity::type, layout::entity::initSeed, layout::entity::index, layout::entity::sprite,
     layout::entity::sprite + layout::sprite::color, layout::entity::damageQueue,
     layout::entity::damageRecordSize, layout::entity::active},
    {layout::game::dimension, layout::game::roomIndex, layout::room::entities,
     layout::entityList::renderArray, layout::entityList::data, layout::entityList::count},
    layout::entityRef::entity,
    j511::entity_cast::npc};
} // namespace isaac::engine::native_combat_feedback

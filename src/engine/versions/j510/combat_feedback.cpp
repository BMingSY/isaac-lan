#include <windows.h>
#include "engine/versions/common/combat_feedback_bindings.h"
#include "engine/versions/j510/entity_cast.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_combat_feedback {
namespace layout = j510::layout;
static_assert(layout::color::size == colorBytes);
// The audited damage SetColor call owns ESI=queue record; the queue-clear
// boundary owns EDI=entity. Both versions share these private hook thunks.
const Bindings bindings{
    j510::entry::npcTakeDamage,
    j510::entry::entitySetColor,
    j510::entry::entityDamageColorReturn,
    j510::entry::entityDamageDrain,
    j510::globals::game,
    {layout::entity::type, layout::entity::initSeed, layout::entity::index, layout::entity::sprite,
     layout::entity::sprite + layout::sprite::color, layout::entity::damageQueue,
     layout::entity::damageRecordSize, layout::entity::active},
    {layout::game::dimension, layout::game::roomIndex, layout::room::entities,
     layout::entityList::renderArray, layout::entityList::data, layout::entityList::count},
    layout::entityRef::entity,
    j510::entity_cast::npc};
} // namespace isaac::engine::native_combat_feedback

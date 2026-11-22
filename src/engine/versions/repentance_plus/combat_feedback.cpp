#include <windows.h>
#include "engine/versions/common/combat_feedback_bindings.h"
#include "engine/versions/repentance_plus/entity_cast.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"

namespace isaac::engine::native_combat_feedback {
namespace layout = repentance_plus::layout;
static_assert(layout::color::size == colorBytes);
// The audited damage SetColor call owns ESI=queue record; the queue-clear
// boundary owns EDI=entity. Both versions share these private hook thunks.
const Bindings bindings{
    repentance_plus::entry::npcTakeDamage,
    repentance_plus::entry::entitySetColor,
    repentance_plus::entry::entityDamageColorReturn,
    repentance_plus::entry::entityDamageDrain,
    repentance_plus::globals::game,
    {layout::entity::type, layout::entity::initSeed, layout::entity::index, layout::entity::sprite,
     layout::entity::sprite + layout::sprite::color, layout::entity::damageQueue,
     layout::entity::damageRecordSize, layout::entity::active},
    {layout::game::dimension, layout::game::roomIndex, layout::room::entities,
     layout::entityList::renderArray, layout::entityList::data, layout::entityList::count},
    layout::entityRef::entity,
    repentance_plus::entity_cast::npc};
} // namespace isaac::engine::native_combat_feedback

#include "engine/versions/common/combat_feedback_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"

namespace isaac::engine::native_combat_feedback {
namespace layout = j460::layout;
static_assert(layout::color::size == colorBytes);
// The audited damage SetColor call owns ESI=queue record; the queue-clear
// boundary owns EDI=entity. Both versions share these private hook thunks.
const Bindings bindings{j460::entry::npcTakeDamage,
                        j460::entry::entitySetColor,
                        j460::entry::entityDamageColorReturn,
                        j460::entry::entityDamageDrain,
                        j460::globals::game,
                        {layout::entity::type, layout::entity::initSeed, layout::entity::index,
                         layout::entity::sprite, layout::entity::sprite + layout::sprite::color,
                         layout::entity::damageQueue, layout::entity::damageRecordSize},
                        {layout::game::dimension, layout::game::roomIndex, layout::room::entities,
                         layout::entityList::renderArray, layout::entityList::data,
                         layout::entityList::count},
                        layout::entityRef::entity};
} // namespace isaac::engine::native_combat_feedback

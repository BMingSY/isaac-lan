#include "engine/versions/common/rewind_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"

namespace isaac::engine::native_rewind {
namespace layout = repentance::layout;
static_assert(layout::progress::counterCount <= lan::Progress{}.counters.size());
const Bindings bindings{repentance::entry::gameStoreHourglass,
                        repentance::entry::engineRoomsTransition,
                        repentance::entry::engineRoomsStageTransition,
                        repentance::entry::roomTransitionStart,
                        repentance::globals::game,
                        {layout::game::rewindBuffers, layout::game::selectedRewindBuffer,
                         layout::game::players, layout::game::roomTransition, layout::game::stage,
                         layout::game::stageType, layout::game::stateFlags},
                        {layout::player::controller, layout::entity::variant,
                         layout::player::hourglassUses, layout::player::hourglassFloorUses},
                        {layout::rewindBuffer::valid, layout::rewindBuffer::state,
                         layout::rewindBuffer::stride, layout::rewindBuffer::door,
                         layout::rewindBuffer::tick, layout::rewindBuffer::counters,
                         layout::progress::counterCount},
                        {layout::roomTransition::state, layout::roomTransition::index,
                         layout::roomTransition::direction, layout::roomTransition::animation,
                         layout::roomTransition::dimension},
                        nullptr};
} // namespace isaac::engine::native_rewind

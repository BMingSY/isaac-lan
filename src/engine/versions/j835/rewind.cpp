#include "engine/versions/common/rewind_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_rewind {
namespace layout = j835::layout;
static_assert(layout::progress::counterCount <= lan::Progress{}.counters.size());
const Bindings bindings{j835::entry::gameStoreHourglass,
                        j835::entry::engineRoomsTransition,
                        j835::entry::engineRoomsStageTransition,
                        j835::entry::roomTransitionStart,
                        j835::globals::game,
                        {layout::game::rewindBuffers, layout::game::selectedRewindBuffer,
                         layout::game::players, layout::game::roomTransition},
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

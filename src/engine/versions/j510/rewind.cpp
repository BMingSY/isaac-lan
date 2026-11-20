#include "engine/versions/common/rewind_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::native_rewind {
namespace layout = j510::layout;
namespace {
void finishReplay(std::uintptr_t game) {
    const auto transition = game + layout::game::roomTransition;
    if (*reinterpret_cast<int*>(transition + layout::roomTransition::state) != 0 &&
        *reinterpret_cast<int*>(transition + layout::roomTransition::active) != 0)
        *reinterpret_cast<int*>(game + layout::game::transitionTailCounter) = 0;
    *reinterpret_cast<bool*>(game + layout::game::transitionTailFlag) = false;
}
} // namespace
static_assert(layout::progress::counterCount <= lan::Progress{}.counters.size());
const Bindings bindings{j510::entry::gameStoreHourglass,
                        j510::entry::engineRoomsTransition,
                        j510::entry::engineRoomsStageTransition,
                        j510::entry::roomTransitionStart,
                        j510::globals::game,
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
                        finishReplay};
} // namespace isaac::engine::native_rewind

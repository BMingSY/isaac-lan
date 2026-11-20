#include "engine/versions/common/sprite_state_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"

namespace isaac::engine::native_sprite {
namespace backend = j835;
namespace layout = backend::layout;
const Bindings bindings{
    backend::entry::animationStateReset,
    {layout::string::size, layout::string::capacity, layout::string::inlineCapacity},
    {layout::sprite::size, layout::sprite::animation, layout::sprite::overlay,
     layout::sprite::shadow, layout::sprite::color, layout::sprite::speed, layout::sprite::flags,
     layout::sprite::overlayFirst, layout::sprite::layers, layout::sprite::layerCount},
    {layout::spriteLayer::size, layout::spriteLayer::data, layout::spriteLayer::id,
     layout::spriteLayer::path, layout::spriteLayer::booleans, layout::spriteLayer::numbers,
     layout::spriteLayer::blend, layout::spriteLayer::flags},
    {layout::animationState::data, layout::animationState::layerFrames,
     layout::animationState::nullFrames, layout::animationState::frame,
     layout::animationState::playing, layout::animationState::events,
     layout::animationState::previousEvents},
    {layout::animationData::layers, layout::animationData::layerCount, layout::animationData::nulls,
     layout::animationData::nullCount, layout::animationData::layerMap,
     layout::animationData::totalFrames, layout::animationData::name},
    {layout::animationLayer::stride, layout::animationLayer::id, layout::animationLayer::frameCount,
     layout::animationLayer::nullFrameCount}};
} // namespace isaac::engine::native_sprite

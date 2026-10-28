#include "engine/versions/common/entity_field_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <limits>

namespace isaac::engine::native_entity_fields {
namespace entry = j460::entry;
namespace layout = j460::layout;
static_assert(layout::color::size == colorBytes);
constinit const Bindings bindings{
    {entry::entityLuaSetSize, entry::entityLuaSetColor, entry::tearSetHeight, entry::tearSetScale,
     entry::pickupSetPrice},
    j460::globals::game,
    {
        {layout::entity::type,         layout::entity::variant,
         layout::entity::subtype,      layout::entity::initSeed,
         layout::entity::positionX,    layout::entity::velocity,
         layout::entity::friction,     layout::entity::hitPoints,
         layout::entity::maxHitPoints, layout::entity::collisionDamage,
         layout::entity::visible,      layout::entity::flipX,
         layout::entity::depthOffset,  layout::entity::mass,
         layout::entity::size,         layout::entity::spriteRotation,
         layout::entity::spriteOffset, layout::entity::spriteScale,
         layout::entity::createdFrame, layout::entity::flags,
         layout::entity::color,        layout::entity::sprite,
         layout::entity::active,       layout::entity::damageVtableSlot},
        {layout::sprite::path, layout::sprite::animation, layout::sprite::overlay,
         layout::sprite::flipX, layout::sprite::flipY, layout::sprite::rotation,
         layout::sprite::scale, layout::sprite::offset, layout::sprite::color,
         layout::sprite::size},
        {layout::color::red, layout::color::green, layout::color::blue, layout::color::alpha,
         layout::color::redOffset, layout::color::greenOffset, layout::color::blueOffset,
         layout::color::size, layout::color::colorizeChannels, layout::color::colorize},
        {layout::tear::fallingAcceleration, layout::tear::fallingSpeed, layout::tear::height,
         layout::tear::rotation, layout::tear::scale, layout::tear::waitFrames},
        {layout::effect::state, layout::effect::timeout, layout::effect::lifeSpan,
         layout::effect::rotation, layout::effect::scale, layout::effect::minRadius,
         layout::effect::maxRadius},
        {layout::familiar::state, layout::familiar::fireCooldown, layout::familiar::headFrameDelay,
         layout::familiar::moveDirection, layout::familiar::shootDirection,
         layout::familiar::lastDirection, layout::familiar::orbitAngleOffset,
         layout::familiar::orbitLayer, layout::familiar::orbitSpeed},
        {layout::pickup::autoUpdatePrice, layout::pickup::charge, layout::pickup::optionsIndex,
         layout::pickup::price, layout::pickup::shopItemId, layout::pickup::state,
         layout::pickup::timeout, layout::pickup::touched, layout::pickup::wait},
        {layout::string::size, layout::string::capacity, layout::string::inlineCapacity},
        {layout::animationState::data, layout::animationState::frame},
        {layout::npc::boss},
        {layout::game::frame},
    },
    -2,
    7};
} // namespace isaac::engine::native_entity_fields

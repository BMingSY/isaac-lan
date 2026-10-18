#pragma once
#include "engine/versions/j460/layout.h"
#include "compat/game_ids.h"
#include <array>
#include <span>
#include <string_view>

namespace isaac::engine::j460::entity_fields {
enum class Kind {
    real,
    integer,
    unsignedInteger,
    boolean,
    vector,
    flags,
    frame,
    color,
    text,
    animationName,
    animationFrame,
    overlayFrame
};
enum class Write { direct, readOnly, size, damage, tearHeight, tearScale, entityColor };
struct Field {
    const char* name;
    Kind kind;
    unsigned offset;
    Write write = Write::direct;
};
// These are the J460 Lua property bindings, not the similarly named fields in
// other versions. Keep the same native setters when they have side effects.
inline constexpr Field common[] = {
    {"Type", Kind::unsignedInteger, layout::entity::type, Write::readOnly},
    {"Variant", Kind::unsignedInteger, layout::entity::variant},
    {"SubType", Kind::unsignedInteger, layout::entity::subtype},
    {"InitSeed", Kind::unsignedInteger, layout::entity::initSeed, Write::readOnly},
    {"Position", Kind::vector, layout::entity::positionX},
    {"Velocity", Kind::vector, layout::entity::velocity},
    {"HitPoints", Kind::real, layout::entity::hitPoints},
    {"MaxHitPoints", Kind::real, layout::entity::maxHitPoints},
    {"CollisionDamage", Kind::real, layout::entity::collisionDamage, Write::damage},
    {"Visible", Kind::boolean, layout::entity::visible},
    {"FlipX", Kind::boolean, layout::entity::flipX},
    {"DepthOffset", Kind::real, layout::entity::depthOffset},
    {"Mass", Kind::real, layout::entity::mass},
    {"Size", Kind::real, layout::entity::size, Write::size},
    {"SpriteRotation", Kind::real, layout::entity::spriteRotation},
    {"SpriteOffset", Kind::vector, layout::entity::spriteOffset},
    {"SpriteScale", Kind::vector, layout::entity::spriteScale},
    {"FrameCount", Kind::frame, layout::entity::createdFrame, Write::readOnly},
    {"EntityFlags", Kind::flags, layout::entity::flags, Write::readOnly},
    {"Color", Kind::color, layout::entity::color, Write::entityColor},
};
inline constexpr unsigned spriteType = 0;
inline constexpr Field sprite[] = {
    {"Filename", Kind::text, layout::sprite::path, Write::readOnly},
    {"Animation", Kind::animationName, layout::sprite::animation, Write::readOnly},
    {"Frame", Kind::animationFrame, layout::sprite::animation, Write::readOnly},
    {"OverlayAnimation", Kind::animationName, layout::sprite::overlay, Write::readOnly},
    {"OverlayFrame", Kind::overlayFrame, layout::sprite::overlay, Write::readOnly},
    {"FlipX", Kind::boolean, layout::sprite::flipX},
    {"FlipY", Kind::boolean, layout::sprite::flipY},
    {"Rotation", Kind::real, layout::sprite::rotation},
    {"Scale", Kind::vector, layout::sprite::scale},
    {"Offset", Kind::vector, layout::sprite::offset},
    {"Color", Kind::color, layout::sprite::color},
};
inline constexpr unsigned colorOffsets[] = {
    layout::color::red,        layout::color::green,     layout::color::blue,
    layout::color::alpha,      layout::color::redOffset, layout::color::greenOffset,
    layout::color::blueOffset,
};
inline constexpr Field tear[] = {
    {"FallingAcceleration", Kind::real, layout::tear::fallingAcceleration},
    {"FallingSpeed", Kind::real, layout::tear::fallingSpeed},
    {"Height", Kind::real, layout::tear::height, Write::tearHeight},
    {"Rotation", Kind::real, layout::tear::rotation},
    {"Scale", Kind::real, layout::tear::scale, Write::tearScale},
    {"WaitFrames", Kind::integer, layout::tear::waitFrames},
};
inline constexpr Field effect[] = {
    {"State", Kind::integer, layout::effect::state},
    {"Timeout", Kind::integer, layout::effect::timeout},
    {"LifeSpan", Kind::integer, layout::effect::lifeSpan},
    {"Rotation", Kind::real, layout::effect::rotation},
    {"Scale", Kind::real, layout::effect::scale},
    {"FallingAcceleration", Kind::real, layout::tear::fallingAcceleration},
    {"FallingSpeed", Kind::real, layout::tear::fallingSpeed},
    {"m_Height", Kind::real, layout::tear::height},
    {"MinRadius", Kind::real, layout::effect::minRadius},
    {"MaxRadius", Kind::real, layout::effect::maxRadius},
};
inline constexpr Field familiar[] = {
    {"State", Kind::integer, layout::familiar::state},
    {"FireCooldown", Kind::integer, layout::familiar::fireCooldown},
    {"HeadFrameDelay", Kind::integer, layout::familiar::headFrameDelay},
    {"MoveDirection", Kind::integer, layout::familiar::moveDirection},
    {"ShootDirection", Kind::integer, layout::familiar::shootDirection},
    {"LastDirection", Kind::integer, layout::familiar::lastDirection},
    {"OrbitAngleOffset", Kind::real, layout::familiar::orbitAngleOffset},
    {"OrbitLayer", Kind::integer, layout::familiar::orbitLayer},
    {"OrbitSpeed", Kind::real, layout::familiar::orbitSpeed},
};
inline bool supported(unsigned type) {
    return type == compat::ids::entity::tear || type == compat::ids::entity::familiar ||
           type == compat::ids::entity::effect;
}
inline const Field* find(unsigned type, std::string_view name) {
    if (type == spriteType) {
        for (const auto& field : sprite)
            if (name == field.name)
                return &field;
        return nullptr;
    }
    for (const auto& field : common)
        if (name == field.name)
            return &field;
    const std::span<const Field> fields =
        type == compat::ids::entity::tear       ? std::span<const Field>(tear)
        : type == compat::ids::entity::familiar ? std::span<const Field>(familiar)
                                                : std::span<const Field>(effect);
    for (const auto& field : fields)
        if (name == field.name)
            return &field;
    return nullptr;
}
} // namespace isaac::engine::j460::entity_fields

#pragma once
#include "engine/versions/common/entity_field_bindings.h"
#include "compat/game_ids.h"
#include <array>
#include <span>
#include <string_view>

namespace isaac::engine::native_entity_fields {
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
enum class Write {
    direct,
    readOnly,
    size,
    damage,
    tearHeight,
    tearScale,
    entityColor,
    pickupPrice,
    shopItem
};
struct Field {
    const char* name;
    Kind kind;
    unsigned offset;
    Write write = Write::direct;
};
// Names and write semantics are shared; the selected backend supplies the audited
// layout and native setters. These descriptors never retain game objects.
inline const auto& offsets = bindings.layout;
inline const Field common[] = {
    {"Type", Kind::unsignedInteger, offsets.entity.type, Write::readOnly},
    {"Variant", Kind::unsignedInteger, offsets.entity.variant},
    {"SubType", Kind::unsignedInteger, offsets.entity.subtype},
    {"InitSeed", Kind::unsignedInteger, offsets.entity.initSeed, Write::readOnly},
    {"Position", Kind::vector, offsets.entity.positionX},
    {"Velocity", Kind::vector, offsets.entity.velocity},
    {"Friction", Kind::real, offsets.entity.friction},
    {"HitPoints", Kind::real, offsets.entity.hitPoints},
    {"MaxHitPoints", Kind::real, offsets.entity.maxHitPoints},
    {"CollisionDamage", Kind::real, offsets.entity.collisionDamage, Write::damage},
    {"Visible", Kind::boolean, offsets.entity.visible},
    {"FlipX", Kind::boolean, offsets.entity.flipX},
    {"DepthOffset", Kind::real, offsets.entity.depthOffset},
    {"Mass", Kind::real, offsets.entity.mass},
    {"Size", Kind::real, offsets.entity.size, Write::size},
    {"SpriteRotation", Kind::real, offsets.entity.spriteRotation},
    {"SpriteOffset", Kind::vector, offsets.entity.spriteOffset},
    {"SpriteScale", Kind::vector, offsets.entity.spriteScale},
    {"FrameCount", Kind::frame, offsets.entity.createdFrame, Write::readOnly},
    {"EntityFlags", Kind::flags, offsets.entity.flags, Write::readOnly},
    {"Color", Kind::color, offsets.entity.color, Write::entityColor},
};
inline constexpr unsigned spriteType = 0;
inline const Field sprite[] = {
    {"Filename", Kind::text, offsets.sprite.path, Write::readOnly},
    {"Animation", Kind::animationName, offsets.sprite.animation, Write::readOnly},
    {"Frame", Kind::animationFrame, offsets.sprite.animation, Write::readOnly},
    {"OverlayAnimation", Kind::animationName, offsets.sprite.overlay, Write::readOnly},
    {"OverlayFrame", Kind::overlayFrame, offsets.sprite.overlay, Write::readOnly},
    {"FlipX", Kind::boolean, offsets.sprite.flipX},
    {"FlipY", Kind::boolean, offsets.sprite.flipY},
    {"Rotation", Kind::real, offsets.sprite.rotation},
    {"Scale", Kind::vector, offsets.sprite.scale},
    {"Offset", Kind::vector, offsets.sprite.offset},
    {"Color", Kind::color, offsets.sprite.color},
};
inline const unsigned colorOffsets[] = {
    offsets.color.red,        offsets.color.green,     offsets.color.blue,
    offsets.color.alpha,      offsets.color.redOffset, offsets.color.greenOffset,
    offsets.color.blueOffset,
};
inline const Field tear[] = {
    {"FallingAcceleration", Kind::real, offsets.tear.fallingAcceleration},
    {"FallingSpeed", Kind::real, offsets.tear.fallingSpeed},
    {"Height", Kind::real, offsets.tear.height, Write::tearHeight},
    {"Rotation", Kind::real, offsets.tear.rotation},
    {"Scale", Kind::real, offsets.tear.scale, Write::tearScale},
    {"WaitFrames", Kind::integer, offsets.tear.waitFrames},
};
inline const Field effect[] = {
    {"State", Kind::integer, offsets.effect.state},
    {"Timeout", Kind::integer, offsets.effect.timeout},
    {"LifeSpan", Kind::integer, offsets.effect.lifeSpan},
    {"Rotation", Kind::real, offsets.effect.rotation},
    {"Scale", Kind::real, offsets.effect.scale},
    {"FallingAcceleration", Kind::real, offsets.tear.fallingAcceleration},
    {"FallingSpeed", Kind::real, offsets.tear.fallingSpeed},
    {"m_Height", Kind::real, offsets.tear.height},
    {"MinRadius", Kind::real, offsets.effect.minRadius},
    {"MaxRadius", Kind::real, offsets.effect.maxRadius},
};
inline const Field familiar[] = {
    {"State", Kind::integer, offsets.familiar.state},
    {"FireCooldown", Kind::integer, offsets.familiar.fireCooldown},
    {"HeadFrameDelay", Kind::integer, offsets.familiar.headFrameDelay},
    {"MoveDirection", Kind::integer, offsets.familiar.moveDirection},
    {"ShootDirection", Kind::integer, offsets.familiar.shootDirection},
    {"LastDirection", Kind::integer, offsets.familiar.lastDirection},
    {"OrbitAngleOffset", Kind::real, offsets.familiar.orbitAngleOffset},
    {"OrbitLayer", Kind::integer, offsets.familiar.orbitLayer},
    {"OrbitSpeed", Kind::real, offsets.familiar.orbitSpeed},
};
inline const Field pickup[] = {
    {"AutoUpdatePrice", Kind::boolean, offsets.pickup.autoUpdatePrice},
    {"Charge", Kind::integer, offsets.pickup.charge},
    {"OptionsPickupIndex", Kind::integer, offsets.pickup.optionsIndex},
    {"Price", Kind::integer, offsets.pickup.price, Write::pickupPrice},
    {"ShopItemId", Kind::integer, offsets.pickup.shopItemId, Write::shopItem},
    {"State", Kind::integer, offsets.pickup.state},
    {"Timeout", Kind::integer, offsets.pickup.timeout},
    {"Touched", Kind::boolean, offsets.pickup.touched},
    {"Wait", Kind::integer, offsets.pickup.wait},
};
inline bool supported(unsigned type) {
    return type == compat::ids::entity::tear || type == compat::ids::entity::familiar ||
           type == compat::ids::entity::effect || type == compat::ids::entity::pickup;
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
        : type == compat::ids::entity::pickup   ? std::span<const Field>(pickup)
                                                : std::span<const Field>(effect);
    for (const auto& field : fields)
        if (name == field.name)
            return &field;
    return nullptr;
}
} // namespace isaac::engine::native_entity_fields

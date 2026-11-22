#pragma once
#include "engine/versions/j511/layout.h"
#include "engine/versions/common/mouse_input.h"

namespace isaac::engine::j511::mouse_input {
using Vector = native_mouse::Vector;
using Aim = native_mouse::Aim;
using ShootingEntity = native_mouse::ShootingEntity;
inline constexpr float aimScale = native_mouse::canonicalScale;
inline constexpr native_mouse::Layout fields{layout::player::controller, layout::entity::positionX,
                                             layout::entity::positionY};
inline Vector origin(void* player, ShootingEntity shootingEntity) {
    return native_mouse::origin(player, shootingEntity, fields);
}
inline lan::PointerInput capture(void* player, Aim original, ShootingEntity shootingEntity) {
    return native_mouse::capture(player, original, shootingEntity, fields,
                                 layout::inputDevice::keyboardId);
}
inline bool replay(void* player, const lan::PointerInput& pointer, Vector* result,
                   ShootingEntity shootingEntity) {
    return native_mouse::replay(player, pointer, result, shootingEntity, fields);
}
} // namespace isaac::engine::j511::mouse_input

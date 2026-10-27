#pragma once
#include "engine/versions/j460/layout.h"
#include "engine/versions/common/mouse_query.h"
#include "net/protocol.h"

namespace isaac::engine::j460::mouse_input {
using Vector = native_mouse::Vector;
using Aim = native_mouse::Aim;
using ShootingEntity = native_mouse::ShootingEntity;
// Native mouse aiming returns (cursor - shooting entity position) * 0.2.
inline constexpr float aimScale = native_mouse::canonicalScale;
inline Vector origin(void* player, ShootingEntity shootingEntity) {
    auto entity = shootingEntity(player);
    const auto address = reinterpret_cast<std::uintptr_t>(entity ? entity : player);
    return {*reinterpret_cast<const float*>(address + layout::entity::positionX),
            *reinterpret_cast<const float*>(address + layout::entity::positionY)};
}
inline lan::PointerInput capture(void* player, Aim original, ShootingEntity shootingEntity) {
    // Only the synchronous physical query borrows keyboard identity. Do not
    // call AssignController or change any device/roster ownership.
    auto& controller = *reinterpret_cast<int*>(reinterpret_cast<std::uintptr_t>(player) +
                                               layout::player::controller);
    struct Restore {
        int& field;
        int value;
        ~Restore() {
            field = value;
        }
    } restore{controller, controller};
    controller = 0;
    Vector aim;
    if (!original(player, &aim, false))
        return {};
    const auto anchor = origin(player, shootingEntity);
    const lan::PointerInput pointer{true, anchor.x + aim.x / aimScale, anchor.y + aim.y / aimScale};
    return lan::validPointer(pointer) ? pointer : lan::PointerInput{};
}
inline bool replay(void* player, const lan::PointerInput& pointer, Vector* result,
                   ShootingEntity shootingEntity) {
    if (!pointer.active || !result)
        return false;
    const auto anchor = origin(player, shootingEntity);
    *result = {(pointer.x - anchor.x) * aimScale, (pointer.y - anchor.y) * aimScale};
    return true;
}
} // namespace isaac::engine::j460::mouse_input

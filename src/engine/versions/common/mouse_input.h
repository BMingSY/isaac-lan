#pragma once
#include "engine/versions/common/mouse_query.h"
#include "net/protocol.h"

namespace isaac::engine::native_mouse {
struct Layout {
    unsigned controller, positionX, positionY;
};
inline Vector origin(void* player, ShootingEntity shootingEntity, const Layout& layout) {
    auto entity = shootingEntity(player);
    const auto address = reinterpret_cast<std::uintptr_t>(entity ? entity : player);
    return {*reinterpret_cast<const float*>(address + layout.positionX),
            *reinterpret_cast<const float*>(address + layout.positionY)};
}
inline lan::PointerInput capture(void* player, Aim original, ShootingEntity shootingEntity,
                                 const Layout& layout) {
    // Only this synchronous physical query borrows keyboard identity. Do not
    // call AssignController or change any device/roster ownership.
    auto& controller =
        *reinterpret_cast<int*>(reinterpret_cast<std::uintptr_t>(player) + layout.controller);
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
    const auto anchor = origin(player, shootingEntity, layout);
    const lan::PointerInput pointer{true, anchor.x + aim.x / canonicalScale,
                                    anchor.y + aim.y / canonicalScale};
    return lan::validPointer(pointer) ? pointer : lan::PointerInput{};
}
inline bool replay(void* player, const lan::PointerInput& pointer, Vector* result,
                   ShootingEntity shootingEntity, const Layout& layout) {
    if (!pointer.active || !result)
        return false;
    const auto anchor = origin(player, shootingEntity, layout);
    *result = {(pointer.x - anchor.x) * canonicalScale, (pointer.y - anchor.y) * canonicalScale};
    return true;
}
} // namespace isaac::engine::native_mouse

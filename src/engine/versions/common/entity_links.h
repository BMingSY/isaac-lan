#pragma once
#include "compat/game_ids.h"
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::native_entity_links {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
struct Layout {
    unsigned type, index, minecart, held;
};
inline constexpr unsigned minecartType = compat::ids::entity::minecart;
inline constexpr unsigned playerType = compat::ids::entity::player;
template <class T> T& field(Address entity, unsigned offset) {
    return *reinterpret_cast<T*>(entity + offset);
}
inline void validate(Address entity, const Layout& layout, Address cart) {
    if (!entity || !field<unsigned>(entity, layout.type) ||
        (cart && field<unsigned>(cart, layout.type) != minecartType) || entity == cart)
        throw std::runtime_error("Invalid entity minecart link");
}
inline int index(Address entity, const Layout& layout) {
    validate(entity, layout, 0);
    const auto cart = field<Address>(entity, layout.minecart);
    validate(entity, layout, cart);
    return cart ? field<int>(cart, layout.index) : -1;
}
template <class Assign>
void restore(Address entity, const Layout& layout, Address cart, Assign assign) {
    validate(entity, layout, cart);
    if (field<Address>(entity, layout.minecart) != cart)
        assign(reinterpret_cast<void*>(entity + layout.minecart), reinterpret_cast<void*>(cart));
}
inline void validateHeld(Address player, const Layout& layout, Address held) {
    if (!player || field<unsigned>(player, layout.type) != playerType || player == held ||
        (held && !field<unsigned>(held, layout.type)))
        throw std::runtime_error("Invalid player held entity link");
}
inline int heldIndex(Address player, const Layout& layout) {
    validateHeld(player, layout, 0);
    const auto held = field<Address>(player, layout.held);
    validateHeld(player, layout, held);
    return held ? field<int>(held, layout.index) : -1;
}
template <class Assign>
void restoreHeld(Address player, const Layout& layout, Address held, Assign assign) {
    validateHeld(player, layout, held);
    if (field<Address>(player, layout.held) != held)
        assign(reinterpret_cast<void*>(player + layout.held), reinterpret_cast<void*>(held));
}
} // namespace isaac::engine::native_entity_links

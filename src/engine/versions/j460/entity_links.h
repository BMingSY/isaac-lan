#pragma once
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::j460::entity_links {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
inline constexpr unsigned minecartOffset = 0x3d4, minecartType = 965;
template <class T> T& field(Address entity, unsigned offset) {
    return *reinterpret_cast<T*>(entity + offset);
}
inline void validate(Address entity, Address cart) {
    if (!entity || !field<unsigned>(entity, 0x28) ||
        (cart && field<unsigned>(cart, 0x28) != minecartType) || entity == cart)
        throw std::runtime_error("Invalid entity minecart link");
}
inline int index(Address entity) {
    validate(entity, 0);
    const auto cart = field<Address>(entity, minecartOffset);
    validate(entity, cart);
    return cart ? field<int>(cart, 0x20) : -1;
}
template <class Assign> void restore(Address entity, Address cart, Assign assign) {
    validate(entity, cart);
    if (field<Address>(entity, minecartOffset) != cart)
        assign(reinterpret_cast<void*>(entity + minecartOffset), reinterpret_cast<void*>(cart));
}
} // namespace isaac::engine::j460::entity_links

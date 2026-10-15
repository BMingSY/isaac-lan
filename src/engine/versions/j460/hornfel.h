#pragma once
#include "compat/game_ids.h"
#include <array>
#include <cstdint>
#include <stdexcept>

namespace isaac::engine::j460::hornfel {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> T& field(Address p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
inline constexpr unsigned bombsOffset = 0xbf0;
// J460 MSVC deque<EntityPtr>: proxy, map, map size, offset, element count.
// The game's resize/EntityPtr assignment retain allocator and observer ownership.
inline std::array<Address, 2> slots(Address entity) {
    if (!entity || field<unsigned>(entity, 0x28) != compat::ids::entity::hornfel)
        throw std::runtime_error("Hornfel bomb links require Hornfel");
    const auto deque = entity + bombsOffset;
    const auto count = field<unsigned>(deque, 16);
    if (!count)
        return {};
    const auto map = field<Address>(deque, 4);
    const auto capacity = field<unsigned>(deque, 8), offset = field<unsigned>(deque, 12);
    if (count != 2 || !map || capacity < 8 || capacity > 65536 || (capacity & (capacity - 1)) ||
        offset >= capacity * 4)
        throw std::runtime_error("Invalid Hornfel bomb container");
    std::array<Address, 2> result{};
    for (unsigned i = 0; i < result.size(); ++i) {
        const auto index = offset + i;
        const auto block = field<Address>(map, ((index / 4) & (capacity - 1)) * 4);
        if (!block)
            throw std::runtime_error("Missing Hornfel bomb block");
        result[i] = block + (index % 4) * 4;
    }
    return result;
}
inline std::array<int, 2> indices(Address entity) {
    const auto current = slots(entity);
    std::array<int, 2> result{-1, -1};
    for (unsigned i = 0; i < current.size(); ++i) {
        const auto bomb = current[i] ? field<Address>(current[i], 0) : 0;
        if (bomb) {
            if (field<unsigned>(bomb, 0x28) != compat::ids::entity::bomb)
                throw std::runtime_error("Invalid Hornfel bomb entity");
            result[i] = field<int>(bomb, 0x20);
        }
    }
    return result;
}
template <class Resize, class Assign>
void restore(Address entity, const std::array<Address, 2>& bombs, Resize resize, Assign assign) {
    auto current = slots(entity);
    for (auto bomb : bombs)
        if (bomb && field<unsigned>(bomb, 0x28) != compat::ids::entity::bomb)
            throw std::runtime_error("Invalid Hornfel bomb entity");
    if (!current[0]) {
        resize(reinterpret_cast<void*>(entity + bombsOffset), 2u);
        current = slots(entity);
        if (!current[0])
            throw std::runtime_error("Hornfel bomb container was not initialized");
    }
    for (unsigned i = 0; i < current.size(); ++i)
        if (field<Address>(current[i], 0) != bombs[i])
            assign(reinterpret_cast<void*>(current[i]), reinterpret_cast<void*>(bombs[i]));
}
} // namespace isaac::engine::j460::hornfel

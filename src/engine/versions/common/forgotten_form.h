#pragma once
#include "compat/characters/traits.h"
#include <cstdint>

namespace isaac::engine::native_forgotten_form {
using Swap = bool(__attribute__((thiscall)) *)(void*, bool, bool);
struct Layout {
    unsigned playerType, coopGhost, subplayer, entityType;
};
template <class T> T read(std::uintptr_t player, unsigned offset) {
    return *reinterpret_cast<const T*>(player + offset);
}
inline bool restore(const Layout& layout, std::uintptr_t player, int desired, Swap swap) {
    if (!player)
        return false;
    const auto current = read<int>(player, layout.playerType);
    if (!compat::characters::forgotten(current) || !compat::characters::forgotten(desired) ||
        read<bool>(player, layout.coopGhost))
        return false;
    const auto hidden = read<std::uintptr_t>(player, layout.subplayer);
    if (!hidden || hidden == player || read<unsigned>(hidden, layout.entityType) != 1)
        return false;
    const auto other = read<int>(hidden, layout.playerType);
    if (!compat::characters::forgotten(other) || current == other)
        return false;
    if (current == desired)
        return true;
    // Force the already-authoritative switch without input cooldown or its
    // transition effects. The engine exchanges state; neither body is replaced.
    return swap(reinterpret_cast<void*>(player), true, true) &&
           read<int>(player, layout.playerType) == desired &&
           read<int>(hidden, layout.playerType) == current;
}
} // namespace isaac::engine::native_forgotten_form

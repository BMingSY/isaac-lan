#pragma once
#include "compat/characters/traits.h"
#include "engine/versions/j460/layout.h"
#include <cstdint>

namespace isaac::engine::j460::forgotten_form {
using Swap = bool(__attribute__((thiscall)) *)(void*, bool, bool);
template <class T> T read(std::uintptr_t player, unsigned offset) {
    return *reinterpret_cast<const T*>(player + offset);
}
inline bool restore(std::uintptr_t player, int desired, Swap swap) {
    const auto current = read<int>(player, layout::player::type);
    if (!compat::characters::forgotten(current) || !compat::characters::forgotten(desired) ||
        read<bool>(player, layout::player::coopGhost))
        return false;
    const auto hidden = read<std::uintptr_t>(player, layout::player::subplayer);
    if (!hidden || hidden == player || read<unsigned>(hidden, layout::entity::type) != 1)
        return false;
    const auto other = read<int>(hidden, layout::player::type);
    if (!compat::characters::forgotten(other) || current == other)
        return false;
    if (current == desired)
        return true;
    // Force the already-authoritative switch without input cooldown or its
    // transition effects. The engine exchanges state; neither body is replaced.
    return swap(reinterpret_cast<void*>(player), true, true) &&
           read<int>(player, layout::player::type) == desired &&
           read<int>(hidden, layout::player::type) == current;
}
} // namespace isaac::engine::j460::forgotten_form

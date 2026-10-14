#pragma once
#include "engine/versions/j460/entrypoints.h"
#include <cstdint>

namespace isaac::engine::j460::menu_context {
template <class T> T read(std::uintptr_t address, unsigned offset) {
    return *reinterpret_cast<const T*>(address + offset);
}
inline bool ready(std::uintptr_t image) {
    if (!image)
        return false;
    const auto manager = read<std::uintptr_t>(image, globals::manager);
    const auto menus = read<std::uintptr_t>(image, globals::menuManager);
    if (!manager || !menus)
        return false;
    const auto file = read<int>(manager, 0x10);
    // The LAN overlay receives input from MainMenu.Update only. A selected
    // save still exists on title/file pages, whose input belongs to the game.
    return read<int>(manager, 8) == 1 && file >= 1 && file <= 3 && read<int>(menus, 0x40) == 3;
}
} // namespace isaac::engine::j460::menu_context

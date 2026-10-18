#pragma once
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"
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
    const auto file = read<int>(manager, layout::manager::saveSlot);
    // The LAN overlay receives input from MainMenu.Update only. A selected
    // save still exists on title/file pages, whose input belongs to the game.
    return read<int>(manager, layout::manager::scene) == scene::menu && file >= 1 &&
           file <= static_cast<int>(saveSlotCount) &&
           read<int>(menus, layout::menuManager::page) == menuPage::main;
}
// Only an explicit LAN return may bypass title/file selection, and only
// after native menus have been rebuilt with an already selected profile.
// The selected-page field is a value; menu objects remain engine-owned.
inline bool returnToMain(std::uintptr_t image) {
    if (!image)
        return false;
    const auto manager = read<std::uintptr_t>(image, globals::manager);
    const auto menus = read<std::uintptr_t>(image, globals::menuManager);
    if (!manager || !menus)
        return false;
    const auto file = read<int>(manager, layout::manager::saveSlot);
    if (read<int>(manager, layout::manager::scene) != scene::menu || file < 1 ||
        file > static_cast<int>(saveSlotCount))
        return false;
    auto& page = *reinterpret_cast<int*>(menus + layout::menuManager::page);
    if (page != menuPage::title && page != menuPage::save && page != menuPage::main)
        return false;
    page = menuPage::main;
    return true;
}
} // namespace isaac::engine::j460::menu_context

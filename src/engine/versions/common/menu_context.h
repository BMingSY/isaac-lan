#pragma once
#include <cstdint>
#include <optional>
#include "presentation/main_menu.h"
namespace isaac::engine::native_menu {
struct Layout {
    unsigned manager, menus, scene, saveSlot, page, inputBlocked, managerInputBlock;
    std::optional<unsigned> starting;
    unsigned selection;
    std::optional<int> onlineSelection;
    int menuScene, titlePage, savePage, mainPage, saveSlots;
};
template <class T> T read(std::uintptr_t address, unsigned offset) {
    return *reinterpret_cast<const T*>(address + offset);
}
inline bool selectedProfile(std::uintptr_t image, const Layout& fields) {
    if (!image)
        return false;
    const auto manager = read<std::uintptr_t>(image, fields.manager);
    if (!manager || !read<std::uintptr_t>(image, fields.menus))
        return false;
    const auto file = read<int>(manager, fields.saveSlot);
    return read<int>(manager, fields.scene) == fields.menuScene && file >= 1 &&
           file <= fields.saveSlots;
}
inline bool ready(std::uintptr_t image, const Layout& fields) {
    return selectedProfile(image, fields) &&
           read<int>(read<std::uintptr_t>(image, fields.menus), fields.page) == fields.mainPage;
}
// A selected file on title/save pages does not authorize normal menu input.
// Only an explicit LAN return may change the page after native menus exist.
inline bool returnToMain(std::uintptr_t image, const Layout& fields) {
    if (!selectedProfile(image, fields))
        return false;
    auto& page = *reinterpret_cast<int*>(read<std::uintptr_t>(image, fields.menus) + fields.page);
    if (page != fields.titlePage && page != fields.savePage && page != fields.mainPage)
        return false;
    page = fields.mainPage;
    return true;
}
inline bool acceptsInput(std::uintptr_t image, const Layout& fields) {
    if (!ready(image, fields))
        return false;
    const auto menus = read<std::uintptr_t>(image, fields.menus),
               manager = read<std::uintptr_t>(image, fields.manager);
    return !read<bool>(menus, fields.inputBlocked) &&
           !read<unsigned>(manager, fields.managerInputBlock) &&
           (!fields.starting || !read<bool>(menus, *fields.starting));
}
inline bool entrySelected(std::uintptr_t image, const Layout& fields, void* menu, bool confirm) {
    return confirm && menu && acceptsInput(image, fields) &&
           read<int>(reinterpret_cast<std::uintptr_t>(menu), fields.selection) ==
               fields.onlineSelection.value_or(presentation::main_menu::online);
}
} // namespace isaac::engine::native_menu

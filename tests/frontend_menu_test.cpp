#include "engine/versions/j460/menu_context.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>

namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> void write(Address address, unsigned offset, T value) {
    *reinterpret_cast<T*>(address + offset) = value;
}
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
} // namespace

int main() {
    namespace native = isaac::engine::j460;
    std::vector<std::byte> imageBytes(0x880000);
    alignas(Address) std::array<std::byte, 0x50> managerBytes{}, menuBytes{};
    const auto image = reinterpret_cast<Address>(imageBytes.data());
    const auto manager = reinterpret_cast<Address>(managerBytes.data());
    const auto menus = reinterpret_cast<Address>(menuBytes.data());
    try {
        require(!native::menu_context::ready(0), "Missing image accepted a LAN overlay");
        require(!native::menu_context::ready(image), "Missing managers accepted a LAN overlay");
        write(image, native::globals::manager, manager);
        require(!native::menu_context::ready(image), "Missing menus accepted a LAN overlay");
        write(image, native::globals::menuManager, menus);
        // A guest can retain file one while Exit Game returns to the title.
        // That is insufficient to open an overlay driven by MainMenu.Update.
        write(manager, 8, 1);
        write(manager, 0x10, 1);
        for (int page = 0; page < 32; ++page) {
            write(menus, 0x40, page);
            require(native::menu_context::ready(image) == (page == 3),
                    "A title/file/character page accepted the MainMenu overlay");
        }
        write(menus, 0x40, 3);
        for (int file = 0; file <= 4; ++file) {
            write(manager, 0x10, file);
            require(native::menu_context::ready(image) == (file >= 1 && file <= 3),
                    "Native file-selection boundary changed");
        }
        write(manager, 0x10, 1);
        for (int scene = 0; scene <= 4; ++scene) {
            write(manager, 8, scene);
            require(native::menu_context::ready(image) == (scene == 1),
                    "A running/loading scene accepted a LAN overlay");
        }
        write(image, native::globals::manager, Address{});
        require(!native::menu_context::ready(image), "Released manager accepted a LAN overlay");
        require(!native::menu_context::returnToMain(image), "Return used a released manager");
        write(image, native::globals::manager, manager);
        for (int scene = 0; scene <= 3; ++scene)
            for (int file = 0; file <= 4; ++file)
                for (int page = 0; page < 5; ++page) {
                    write(manager, native::layout::manager::scene, scene);
                    write(manager, native::layout::manager::saveSlot, file);
                    write(menus, native::layout::menuManager::page, page);
                    const bool valid = scene == native::scene::menu && file >= 1 && file <= 3 &&
                                       page >= native::menuPage::title &&
                                       page <= native::menuPage::main;
                    require(native::menu_context::returnToMain(image) == valid,
                            "Return crossed a cinematic/profile/menu ownership boundary");
                    require(
                        native::menu_context::read<int>(menus, native::layout::menuManager::page) ==
                            (valid ? native::menuPage::main : page),
                        "Return changed an unrelated native page");
                }
        write(image, native::globals::menuManager, Address{});
        require(!native::menu_context::returnToMain(image), "Return used a released menu");
        std::cout << "PASS native frontend title/file/main readiness and cleanup boundaries\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

#include "engine/versions/common/frontend_bindings.h"
#include "test_support.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <vector>
namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> void write(Address object, unsigned offset, T value) {
    *reinterpret_cast<T*>(object + offset) = value;
}
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned managerGlobal = 0x7fd680, menusGlobal = 0x7fd688;
constexpr unsigned pageOffset = 0x38, blockedOffset = 0x20, managerBlock = 0x4a268;
constexpr bool official = false;
#else
constexpr unsigned managerGlobal = 0x89a0d4, menusGlobal = 0x89a8e4;
constexpr unsigned pageOffset = 0x40, blockedOffset = 0xd, managerBlock = 0x4d44c;
constexpr bool official = true;
#endif
} // namespace
int main() {
    namespace context = isaac::engine::native_menu;
    const auto& fields = isaac::engine::native_frontend::bindings.menu;
    std::vector<std::byte> imageBytes(privateGameImageBytes), managerBytes(0x4e000);
    std::array<std::byte, 0x50> menuBytes{}, mainBytes{};
    const auto image = reinterpret_cast<Address>(imageBytes.data());
    const auto manager = reinterpret_cast<Address>(managerBytes.data());
    const auto menus = reinterpret_cast<Address>(menuBytes.data());
    const auto ready = [&] { return context::ready(image, fields); };
    const auto accepts = [&] { return context::acceptsInput(image, fields); };
    const auto entry = [&](bool confirm, bool alternate) {
        return context::entrySelected(image, fields, mainBytes.data(), confirm, alternate);
    };
    try {
        require(!context::ready(0, fields) && !ready(),
                "Missing image/managers accepted a LAN overlay");
        write(image, managerGlobal, manager);
        require(!ready(), "Missing menus accepted a LAN overlay");
        write(image, menusGlobal, menus);
        write(manager, 8, 1);
        write(manager, 0x10, 1);
        for (int page = 0; page < 32; ++page) {
            write(menus, pageOffset, page);
            require(ready() == (page == 3),
                    "Title/file/character page accepted the MainMenu overlay");
        }
        write(menus, pageOffset, 3);
        for (int file = 0; file <= 4; ++file) {
            write(manager, 0x10, file);
            require(ready() == (file >= 1 && file <= 3), "File-selection boundary changed");
        }
        write(manager, 0x10, 1);
        for (int scene = 0; scene <= 4; ++scene) {
            write(manager, 8, scene);
            require(ready() == (scene == 1), "Running/loading scene accepted a LAN overlay");
        }
        write(manager, 8, 1);
        require(accepts(), "Main menu rejects normal input");
        for (int selection = 0; selection < 7; ++selection) {
            write(reinterpret_cast<Address>(mainBytes.data()), 4, selection);
            require(entry(true, false) == (official && selection == 2),
                    "LAN entry captured an ordinary native confirm action");
            require(entry(false, true) == !official,
                    "Version-specific LAN entry rejected its input");
            require(!entry(false, false), "LAN menu opened without an input action");
        }
        write(menus, blockedOffset, true);
        require(!accepts() && !entry(true, true), "Blocked native menu accepted LAN input");
        write(menus, blockedOffset, false);
        write(manager, managerBlock, 1u);
        require(!accepts() && !entry(true, true), "Blocked manager accepted LAN input");
        write(manager, managerBlock, 0u);
#ifdef ISAAC_LAN_TEST_J835
        write(menus, 1, true);
        require(!accepts() && !entry(true, true),
                "Pending vanilla Continue was interrupted by LAN entry");
        write(menus, 1, false);
#endif
        require(!context::entrySelected(image, fields, nullptr, true, true),
                "Missing main menu accepted entry");
        write(image, managerGlobal, Address{});
        require(!ready() && !context::returnToMain(image, fields),
                "Released manager accepted a LAN return");
        write(image, managerGlobal, manager);
        for (int scene = 0; scene <= 3; ++scene)
            for (int file = 0; file <= 4; ++file)
                for (int page = 0; page < 8; ++page) {
                    write(manager, 8, scene);
                    write(manager, 0x10, file);
                    write(menus, pageOffset, page);
                    auto expectedMenu = menuBytes;
                    const auto expectedManager = managerBytes;
                    const bool valid =
                        scene == 1 && file >= 1 && file <= 3 && page >= 1 && page <= 3;
                    if (valid)
                        write(reinterpret_cast<Address>(expectedMenu.data()), pageOffset, 3);
                    require(context::returnToMain(image, fields) == valid,
                            "Return crossed a cinematic/profile/menu ownership boundary");
                    require(menuBytes == expectedMenu && managerBytes == expectedManager,
                            "Return modified native ownership or unrelated state");
                }
        write(image, menusGlobal, Address{});
        require(!context::returnToMain(image, fields), "Return used a released menu");
        std::cout << "Frontend title/file/main, native input and LAN return boundaries passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

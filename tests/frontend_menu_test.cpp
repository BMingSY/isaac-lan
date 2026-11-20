#include "presentation/main_menu.h"
#include "engine/versions/common/frontend_bindings.h"
#include "test_support.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/layout.h"
#endif
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
std::array<float*, 8> layerPositions;
std::array<float, 8> drawnPositions;
int paperDraws = 0;
void __attribute__((thiscall)) observePaper(void*) {
    ++paperDraws;
    for (unsigned i = 0; i < layerPositions.size(); ++i)
        drawnPositions[i] = *layerPositions[i];
}
void checkPaperDrawing(Address image, Address menus) {
    namespace layout = isaac::engine::j835::layout;
    namespace rows = isaac::presentation::main_menu;
    const auto draw = isaac::engine::native_frontend::bindings.insertedRow.value().draw;
    std::array<std::byte, layout::mainMenu::sprite + layout::sprite::size> storage{};
    const auto menu = reinterpret_cast<Address>(storage.data()),
               sprite = menu + layout::mainMenu::sprite;
    // Reordered localized art, with an unrelated layer between cursor and labels.
    std::array<unsigned, 8> ids{6, 23, 5, 4, 12, 3, 2, 1};
    std::array<std::array<std::byte, layout::spriteLayer::size>, 8> layers{};
    std::array<float, 8> baseline{};
    for (unsigned i = 0; i < ids.size(); ++i) {
        const auto layer = reinterpret_cast<Address>(layers[i].data());
        write(layer, layout::spriteLayer::data, reinterpret_cast<Address>(&ids[i]));
        layerPositions[i] = reinterpret_cast<float*>(layer + layout::spriteLayer::positionY);
        baseline[i] = *layerPositions[i] = 0.75f * i;
    }
    write(sprite, layout::sprite::loaded, true);
    write(sprite, layout::sprite::layers, reinterpret_cast<Address>(layers.data()));
    write(sprite, layout::sprite::layerCount, static_cast<int>(layers.size()));
    write(menu, layout::mainMenu::selection, 2);
    write(menu, layout::mainMenu::positionX, 0.f);
    write(menu, layout::mainMenu::positionY, 540.f);
    write(menus, layout::menuManager::viewX, 79.5f);
    write(menus, layout::menuManager::viewY, -341.25f);
    const auto position = draw(image, storage.data(), true, observePaper);
    require(position && position->x == 79.5f && position->y == 198.75f && paperDraws == 1,
            "A moving main menu did not use the native paper's exact draw origin");
    require(drawnPositions[0] ==
                    baseline[0] + rows::cursorY[rows::online] - rows::nativeCursorY[2] &&
                drawnPositions[1] == baseline[1] &&
                drawnPositions[7] == baseline[7] + rows::rowOffset(0),
            "Drawing moved the wrong native cursor, label, or decoration");
    for (unsigned i = 0; i < ids.size(); ++i)
        require(*layerPositions[i] == baseline[i],
                "Native menu retained a borrowed layer position");
    ids[7] = 24;
    require(!draw(image, storage.data(), true, observePaper) && paperDraws == 2 &&
                drawnPositions == baseline,
            "Incomplete menu art did not use one unmodified native draw");
}
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
#ifdef ISAAC_LAN_TEST_J835
        checkPaperDrawing(image, menus);
#else
        require(!isaac::engine::native_frontend::bindings.insertedRow,
                "Plus already owns an Online row and must draw its native paper unchanged");
#endif
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
            require(!entry(false, true), "Moving onto the LAN row opened it without confirmation");
            require(entry(true, true) == (!official || selection == 2),
                    "Confirm did not open the highlighted LAN entry");
            require(!entry(false, false), "LAN menu opened without an input action");
        }
        namespace rows = isaac::presentation::main_menu;
        require(rows::crossesOnline(0, 2, false, true) && rows::crossesOnline(2, 1, true, false) &&
                    !rows::crossesOnline(5, 0, false, true) &&
                    !rows::crossesOnline(0, 5, true, false),
                "Insertion changed disabled Continue or wraparound navigation");
        for (const rows::Position paper : {rows::Position{0, 0}, {75, 150}, {-120, -40}}) {
            for (int row = 0; row < 7; ++row)
                require(rows::hitsOnline(paper, paper.x + rows::labelX,
                                         paper.y + rows::cursorY[row]) == (row == rows::online),
                        "Mouse hit box did not follow the paper or captured a native row");
            require(!rows::hitsOnline(paper, 30, 246),
                    "The old corner shortcut still accepts input");
        }
        require(rows::labelVisible({-10, 0}, 460, 270) &&
                    rows::labelVisible({-10, 100}, 460, 270) &&
                    !rows::labelVisible({-10, 270}, 460, 270),
                "The printed entry must leave the screen with its paper");
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

#include "presentation/main_menu.h"
#include "engine/versions/common/frontend_bindings.h"
#include "test_support.h"
#ifdef ISAAC_LAN_TEST_REPENTANCE
#include "engine/versions/repentance/layout.h"
#endif
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <vector>
namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> void write(Address object, unsigned offset, T value) {
    *reinterpret_cast<T*>(object + offset) = value;
}
#ifdef ISAAC_LAN_TEST_REPENTANCE
constexpr unsigned managerGlobal = 0x7fd680, menusGlobal = 0x7fd688;
constexpr unsigned pageOffset = 0x38, blockedOffset = 0x20, managerBlock = 0x4a268;

std::array<float*, 8> layerPositions;
std::array<float, 8> drawnPositions;
int paperDraws = 0;
void __attribute__((thiscall)) observePaper(void*) {
    ++paperDraws;
    for (unsigned i = 0; i < layerPositions.size(); ++i)
        drawnPositions[i] = *layerPositions[i];
}
void checkNativeRows(Address image) {
    const auto install =
        isaac::engine::native_frontend::bindings.insertedRow.value().installNavigation;
    const auto confirm = reinterpret_cast<unsigned char*>(image + 0x4d95e0);
    const auto dispatch = reinterpret_cast<unsigned char*>(image + 0x4d95e9);
    const auto up = reinterpret_cast<unsigned char*>(image + 0x4d9a93);
    const auto down = reinterpret_cast<unsigned char*>(image + 0x4d9b05);
    const Address table = image + 0x4d9f58;
    const std::array<Address, 6> stock{image + 0x4d95f0, image + 0x4d969e, image + 0x4d9750,
                                       image + 0x4d97e7, image + 0x4d98a2, image + 0x4d9950};
    std::memcpy(confirm, "\x83\xf8\x05", 3);
    std::memcpy(dispatch, "\xff\x24\x85", 3);
    std::memcpy(dispatch + 3, &table, sizeof(table));
    std::memcpy(up, "\xba\x05\x00\x00\x00", 5);
    std::memcpy(down, "\x83\xf9\x06", 3);
    require(!install(image) && confirm[2] == 5 && up[1] == 5 && down[2] == 6,
            "A mismatched action table must leave native navigation untouched");
    std::memcpy(reinterpret_cast<void*>(table), stock.data(), sizeof(stock));
    require(install(image) && install(image),
            "Stock seven-row navigation must install idempotently");
    Address extended;
    std::memcpy(&extended, dispatch + 3, sizeof(extended));
    const auto* actions = reinterpret_cast<const Address*>(extended);
    require(confirm[2] == 6 && up[1] == 6 && down[2] == 7 && actions[2] == image + 0x4d9c6d,
            "Confirm or wrap boundaries lost the seventh menu option");
    for (unsigned i = 0; i < stock.size(); ++i)
        require(actions[isaac::presentation::main_menu::displayRow(i)] == stock[i],
                "An original menu item changed its native confirm action");
}
void checkPaperDrawing(Address image, Address menus) {
    namespace layout = isaac::engine::repentance::layout;
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
    // The animation's cursor frame may still belong to a previous update.
    std::array<std::byte, layout::animationData::layerMap + 7 * sizeof(int)> animData{};
    std::array<std::byte, layout::animationLayer::stride> cursorLayer{};
    int nativeCursorFrame = 5;
    const auto anim = sprite + layout::sprite::animation;
    write(anim, layout::animationState::data, reinterpret_cast<Address>(animData.data()));
    write(anim, layout::animationState::layerFrames, reinterpret_cast<Address>(&nativeCursorFrame));
    const auto data = reinterpret_cast<Address>(animData.data());
    write(data, layout::animationData::layers, reinterpret_cast<Address>(cursorLayer.data()));
    write(data, layout::animationData::layerCount, 1);
    write(reinterpret_cast<Address>(cursorLayer.data()), layout::animationLayer::id, 6u);
    write(reinterpret_cast<Address>(cursorLayer.data()), layout::animationLayer::frameCount, 6u);
    write(menu, layout::mainMenu::selection, 2);
    write(menu, layout::mainMenu::positionX, 0.f);
    write(menu, layout::mainMenu::positionY, 540.f);
    write(menus, layout::menuManager::viewX, 79.5f);
    write(menus, layout::menuManager::viewY, -341.25f);
    const auto position = draw(image, storage.data(), observePaper);
    require(position && position->x == 79.5f && position->y == 198.75f && paperDraws == 1,
            "A moving main menu did not use the native paper's exact draw origin");
    require(drawnPositions[0] ==
                    baseline[0] + rows::cursorY[rows::online] - rows::nativeCursorY.front() &&
                drawnPositions[1] == baseline[1] &&
                drawnPositions[7] == baseline[7] + rows::rowOffset(0),
            "Drawing moved the wrong native cursor, label, or decoration");
    for (unsigned i = 0; i < ids.size(); ++i)
        require(*layerPositions[i] == baseline[i],
                "Native menu retained a borrowed layer position");
    require(nativeCursorFrame == 5, "Borrowed native cursor frame was not restored");
    ids[7] = 24;
    require(!draw(image, storage.data(), observePaper) && paperDraws == 2 &&
                drawnPositions == baseline,
            "Incomplete menu art did not use one unmodified native draw");
}
#else
constexpr unsigned managerGlobal = 0x89b194, menusGlobal = 0x89b9a4;
constexpr unsigned pageOffset = 0x40, blockedOffset = 0xd, managerBlock = 0x4d444;

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
    const auto entry = [&](bool confirm) {
        return context::entrySelected(image, fields, mainBytes.data(), confirm);
    };
    try {
        require(!context::ready(0, fields) && !ready(),
                "Missing image/managers accepted a LAN overlay");
        write(image, managerGlobal, manager);
        require(!ready(), "Missing menus accepted a LAN overlay");
        write(image, menusGlobal, menus);
#ifdef ISAAC_LAN_TEST_REPENTANCE
        checkNativeRows(image);
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
            require(entry(true) == (selection == 2), "Only the native Online row may open LAN");
            require(!entry(false), "Moving onto a row must not confirm it");
        }
        namespace rows = isaac::presentation::main_menu;
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
        require(!accepts() && !entry(true), "Blocked native menu accepted LAN input");
        write(menus, blockedOffset, false);
        write(manager, managerBlock, 1u);
        require(!accepts() && !entry(true), "Blocked manager accepted LAN input");
        write(manager, managerBlock, 0u);
#ifdef ISAAC_LAN_TEST_REPENTANCE
        write(menus, 1, true);
        require(!accepts() && !entry(true),
                "Pending vanilla Continue was interrupted by LAN entry");
        write(menus, 1, false);
#endif
        require(!context::entrySelected(image, fields, nullptr, true),
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

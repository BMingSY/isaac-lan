#include "engine/versions/common/frontend_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include "engine/versions/j835/menu_state.h"
#include "presentation/main_menu.h"
namespace isaac::engine::native_frontend {
namespace backend = j835;
namespace layout = backend::layout;
namespace {
namespace rows = presentation::main_menu;
using Address = std::uintptr_t;
template <class T> T& field(Address owner, unsigned offset) {
    return *reinterpret_cast<T*>(owner + offset);
}
std::optional<rows::Position> renderInsertedRow(Address image, void* instance, bool focused,
                                                DrawMainMenu render) {
    const auto menus = field<Address>(image, backend::globals::menuManager);
    const auto menu = reinterpret_cast<Address>(instance);
    if (!menus || !menu) {
        render(instance);
        return std::nullopt;
    }
    // Menu_Game::Render places the native paper at its world position plus the
    // current menu camera, including every intermediate frame of a page slide.
    const rows::Position paper{field<float>(menus, layout::menuManager::viewX) +
                                   field<float>(menu, layout::mainMenu::positionX),
                               field<float>(menus, layout::menuManager::viewY) +
                                   field<float>(menu, layout::mainMenu::positionY)};
    const auto sprite = menu + layout::mainMenu::sprite;
    const auto first = field<Address>(sprite, layout::sprite::layers);
    const int count = field<int>(sprite, layout::sprite::layerCount);
    const int selected = field<int>(menu, layout::mainMenu::selection);
    // These are the six printed choices and the cursor in J835's GameMenu
    // animation. Read their layer IDs because localized sheets may reorder them.
    constexpr std::array<unsigned, 7> ids{1, 2, 3, 12, 4, 5, 6};
    constexpr int maxMenuLayers = 64;
    std::array<float*, ids.size()> positions{};
    if (field<bool>(sprite, layout::sprite::loaded) && first && count > 0 &&
        count <= maxMenuLayers && selected >= 0 &&
        selected < static_cast<int>(rows::nativeCursorY.size())) {
        for (int i = 0; i < count; ++i) {
            const auto layer = first + i * layout::spriteLayer::size;
            const auto data = field<Address>(layer, layout::spriteLayer::data);
            if (!data)
                continue;
            const auto id = field<unsigned>(data, layout::spriteLayer::id);
            for (std::size_t row = 0; row < ids.size(); ++row)
                if (id == ids[row])
                    positions[row] = &field<float>(layer, layout::spriteLayer::positionY);
        }
    }
    for (auto position : positions)
        if (!position) {
            render(instance);
            return std::nullopt;
        }
    struct Restore {
        std::array<float*, ids.size()>& positions;
        std::array<float, ids.size()> original{};
        ~Restore() {
            for (std::size_t i = 0; i < positions.size(); ++i)
                *positions[i] = original[i];
        }
    } restore{positions};
    for (std::size_t i = 0; i < positions.size(); ++i)
        restore.original[i] = *positions[i];
    for (unsigned i = 0; i < rows::nativeCursorY.size(); ++i)
        *positions[i] += rows::rowOffset(i);
    *positions.back() += focused ? rows::cursorY[rows::online] - rows::nativeCursorY[selected]
                                 : rows::rowOffset(selected);
    render(instance);
    return paper;
}
} // namespace
const Bindings bindings{
    backend::entry::luaEngineInit,
    backend::entry::menuGameUpdate,
    backend::entry::menuManagerRender,
    layout::luaEngine::state,
    backend::globals::logicalWidth,
    backend::globals::logicalHeight,
    {backend::globals::manager, backend::globals::menuManager, layout::manager::scene,
     layout::manager::saveSlot, layout::menuManager::page, layout::menuManager::inputBlocked,
     layout::manager::menuInputBlock, layout::menuManager::starting, layout::mainMenu::selection,
     std::nullopt, backend::scene::menu, backend::menuPage::title, backend::menuPage::save,
     backend::menuPage::main, backend::saveSlotCount},
    InsertedRow{backend::entry::menuGameRender, renderInsertedRow}};
} // namespace isaac::engine::native_frontend

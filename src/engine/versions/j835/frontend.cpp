#include "engine/versions/common/frontend_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include "engine/versions/j835/menu_navigation.h"
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
std::optional<rows::Position> renderInsertedRow(Address image, void* instance,
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
    float* cursorX = nullptr;
    int* cursorFrame = nullptr;
    if (field<bool>(sprite, layout::sprite::loaded) && first && count > 0 &&
        count <= maxMenuLayers && selected >= 0 &&
        selected < static_cast<int>(rows::cursorY.size())) {
        for (int i = 0; i < count; ++i) {
            const auto layer = first + i * layout::spriteLayer::size;
            const auto data = field<Address>(layer, layout::spriteLayer::data);
            if (!data)
                continue;
            const auto id = field<unsigned>(data, layout::spriteLayer::id);
            if (id == ids.back())
                cursorX = &field<float>(layer, layout::spriteLayer::positionX);
            for (std::size_t row = 0; row < ids.size(); ++row)
                if (id == ids[row])
                    positions[row] = &field<float>(layer, layout::spriteLayer::positionY);
        }
        const auto animation = sprite + layout::sprite::animation;
        const auto data = field<Address>(animation, layout::animationState::data);
        const auto frames = field<Address>(animation, layout::animationState::layerFrames);
        if (data && frames) {
            const auto layers = field<Address>(data, layout::animationData::layers);
            const auto layerCount = field<int>(data, layout::animationData::layerCount);
            const int order =
                field<int>(data, layout::animationData::layerMap + ids.back() * sizeof(int));
            if (layers && order >= 0 && order < layerCount && layerCount <= maxMenuLayers) {
                const auto cursor = layers + order * layout::animationLayer::stride;
                if (field<unsigned>(cursor, layout::animationLayer::id) == ids.back() &&
                    field<unsigned>(cursor, layout::animationLayer::frameCount) ==
                        rows::nativeCursorY.size())
                    cursorFrame = &field<int>(frames, order * sizeof(int));
            }
        }
    }
    if (!cursorX || !cursorFrame) {
        render(instance);
        return std::nullopt;
    }
    for (auto position : positions)
        if (!position) {
            render(instance);
            return std::nullopt;
        }
    struct Restore {
        std::array<float*, ids.size()>& positions;
        float& cursorX;
        int& cursorFrame;
        const float originalX;
        const int originalFrame;
        std::array<float, ids.size()> original{};
        ~Restore() {
            for (std::size_t i = 0; i < positions.size(); ++i)
                *positions[i] = original[i];
            cursorX = originalX;
            cursorFrame = originalFrame;
        }
    } restore{positions, *cursorX, *cursorFrame, *cursorX, *cursorFrame};
    for (std::size_t i = 0; i < positions.size(); ++i)
        restore.original[i] = *positions[i];
    for (unsigned i = 0; i < rows::nativeCursorY.size(); ++i)
        *positions[i] += rows::rowOffset(i);
    // All original cursor poses use the same arrow art. Borrow its first pose
    // at the selected row, including the frame when the LAN overlay returns.
    *cursorFrame = 0;
    *cursorX += rows::cursorX[selected] - rows::nativeCursorX.front();
    *positions.back() += rows::cursorY[selected] - rows::nativeCursorY.front();
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
    InsertedRow{backend::entry::menuGameRender, backend::menu_navigation::install,
                renderInsertedRow}};
} // namespace isaac::engine::native_frontend

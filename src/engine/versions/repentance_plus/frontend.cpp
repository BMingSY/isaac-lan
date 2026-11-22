#include "engine/versions/common/frontend_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/menu_state.h"
namespace isaac::engine::native_frontend {
namespace backend = repentance_plus;
namespace layout = backend::layout;
const Bindings bindings{
    backend::entry::luaEngineInit,
    backend::entry::menuGameUpdate,
    backend::entry::menuManagerRender,
    layout::luaEngine::state,
    backend::globals::logicalWidth,
    backend::globals::logicalHeight,
    {backend::globals::manager, backend::globals::menuManager, layout::manager::scene,
     layout::manager::saveSlot, layout::menuManager::page, layout::menuManager::inputBlocked,
     layout::manager::menuInputBlock, std::nullopt, layout::mainMenu::selection,
     backend::mainMenuSelection::online, backend::scene::menu, backend::menuPage::title,
     backend::menuPage::save, backend::menuPage::main, backend::saveSlotCount}};
} // namespace isaac::engine::native_frontend

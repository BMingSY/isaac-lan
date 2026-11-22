#include "engine/versions/common/pause_bindings.h"
#include "engine/versions/j511/entrypoints.h"
#include "engine/versions/j511/layout.h"
#include "engine/versions/j511/menu_state.h"

namespace isaac::engine::native_pause {
const Bindings bindings{j511::globals::game,
                        j511::globals::manager,
                        j511::entry::pauseMenuShow,
                        j511::entry::pauseMenuHide,
                        j511::entry::pauseMenuControls,
                        j511::entry::optionsSave,
                        j511::layout::game::pauseMenu,
                        j511::layout::game::players,
                        j511::layout::player::controller,
                        j511::layout::manager::options,
                        j511::layout::options::pauseOnFocusLost,
                        j511::layout::pauseMenu::selection,
                        j511::layout::pauseMenu::options,
                        j511::layout::pauseOptions::selection,
                        j511::layout::pauseOptions::entries,
                        j511::layout::pauseMenu::playerIndex,
                        j511::pausePage::root,
                        j511::pausePage::options,
                        j511::pauseSelection::resume,
                        j511::pauseSelection::exit,
                        j511::pauseOption::controller};
} // namespace isaac::engine::native_pause

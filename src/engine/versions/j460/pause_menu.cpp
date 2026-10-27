#include "engine/versions/common/pause_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"

namespace isaac::engine::native_pause {
const Bindings bindings{j460::globals::game,
                        j460::globals::manager,
                        j460::entry::pauseMenuShow,
                        j460::entry::pauseMenuHide,
                        j460::entry::pauseMenuControls,
                        j460::entry::optionsSave,
                        j460::layout::game::pauseMenu,
                        j460::layout::game::players,
                        j460::layout::player::controller,
                        j460::layout::manager::options,
                        j460::layout::pauseMenu::selection,
                        j460::layout::pauseMenu::options,
                        j460::layout::pauseOptions::selection,
                        j460::layout::pauseOptions::entries,
                        j460::layout::pauseMenu::playerIndex,
                        j460::pausePage::root,
                        j460::pausePage::options,
                        j460::pauseSelection::resume,
                        j460::pauseSelection::exit,
                        j460::pauseOption::controller};
} // namespace isaac::engine::native_pause

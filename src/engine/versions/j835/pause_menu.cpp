#include "engine/versions/common/pause_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include "engine/versions/j835/menu_state.h"

namespace isaac::engine::native_pause {
const Bindings bindings{j835::globals::game,
                        j835::globals::manager,
                        j835::entry::pauseMenuShow,
                        j835::entry::pauseMenuHide,
                        j835::entry::pauseMenuControls,
                        j835::entry::optionsSave,
                        j835::layout::game::pauseMenu,
                        j835::layout::game::players,
                        j835::layout::player::controller,
                        j835::layout::manager::options,
                        j835::layout::pauseMenu::selection,
                        j835::layout::pauseMenu::options,
                        j835::layout::pauseOptions::selection,
                        j835::layout::pauseOptions::entries,
                        std::nullopt,
                        j835::pausePage::root,
                        j835::pausePage::options,
                        j835::pauseSelection::resume,
                        j835::pauseSelection::exit,
                        j835::pauseOption::controller};
} // namespace isaac::engine::native_pause

#include "engine/versions/common/pause_bindings.h"
#include "engine/versions/j510/entrypoints.h"
#include "engine/versions/j510/layout.h"
#include "engine/versions/j510/menu_state.h"

namespace isaac::engine::native_pause {
const Bindings bindings{j510::globals::game,
                        j510::globals::manager,
                        j510::entry::pauseMenuShow,
                        j510::entry::pauseMenuHide,
                        j510::entry::pauseMenuControls,
                        j510::entry::optionsSave,
                        j510::layout::game::pauseMenu,
                        j510::layout::game::players,
                        j510::layout::player::controller,
                        j510::layout::manager::options,
                        j510::layout::options::pauseOnFocusLost,
                        j510::layout::pauseMenu::selection,
                        j510::layout::pauseMenu::options,
                        j510::layout::pauseOptions::selection,
                        j510::layout::pauseOptions::entries,
                        j510::layout::pauseMenu::playerIndex,
                        j510::pausePage::root,
                        j510::pausePage::options,
                        j510::pauseSelection::resume,
                        j510::pauseSelection::exit,
                        j510::pauseOption::controller};
} // namespace isaac::engine::native_pause

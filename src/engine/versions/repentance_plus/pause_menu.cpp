#include "engine/versions/common/pause_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/menu_state.h"

namespace isaac::engine::native_pause {
const Bindings bindings{repentance_plus::globals::game,
                        repentance_plus::globals::manager,
                        repentance_plus::entry::pauseMenuShow,
                        repentance_plus::entry::pauseMenuHide,
                        repentance_plus::entry::pauseMenuControls,
                        repentance_plus::entry::optionsSave,
                        repentance_plus::layout::game::pauseMenu,
                        repentance_plus::layout::game::players,
                        repentance_plus::layout::player::controller,
                        repentance_plus::layout::manager::options,
                        repentance_plus::layout::options::pauseOnFocusLost,
                        repentance_plus::layout::pauseMenu::selection,
                        repentance_plus::layout::pauseMenu::options,
                        repentance_plus::layout::pauseOptions::selection,
                        repentance_plus::layout::pauseOptions::entries,
                        repentance_plus::layout::pauseMenu::playerIndex,
                        repentance_plus::pausePage::root,
                        repentance_plus::pausePage::options,
                        repentance_plus::pauseSelection::resume,
                        repentance_plus::pauseSelection::exit,
                        repentance_plus::pauseOption::controller};
} // namespace isaac::engine::native_pause

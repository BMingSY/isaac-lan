#include "engine/versions/common/pause_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/menu_state.h"

namespace isaac::engine::native_pause {
const Bindings bindings{repentance::globals::game,
                        repentance::globals::manager,
                        repentance::entry::pauseMenuShow,
                        repentance::entry::pauseMenuHide,
                        repentance::entry::pauseMenuControls,
                        repentance::entry::optionsSave,
                        repentance::layout::game::pauseMenu,
                        repentance::layout::game::players,
                        repentance::layout::player::controller,
                        repentance::layout::manager::options,
                        repentance::layout::options::pauseOnFocusLost,
                        repentance::layout::pauseMenu::selection,
                        repentance::layout::pauseMenu::options,
                        repentance::layout::pauseOptions::selection,
                        repentance::layout::pauseOptions::entries,
                        std::nullopt,
                        repentance::pausePage::root,
                        repentance::pausePage::options,
                        repentance::pauseSelection::resume,
                        repentance::pauseSelection::exit,
                        repentance::pauseOption::controller};
} // namespace isaac::engine::native_pause

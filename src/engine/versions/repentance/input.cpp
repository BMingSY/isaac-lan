#include "engine/versions/common/input_bindings.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/input_actions.h"
#include "engine/versions/repentance/input_queries.h"
#include "engine/versions/repentance/mouse_input.h"

namespace isaac::engine::native_input {
namespace {
bool installQuery(std::uintptr_t image, Detour detour, Query& original,
                  void (*)(const std::string&)) {
    return repentance::input_queries::install(image, detour, original);
}
int nativeAction(int action) {
    if (action == input::action::restart)
        return repentance::input_actions::restart;
    if (action == input::action::emote)
        return -1;
    return action;
}
void resetMenuPrompts(std::uintptr_t) {
    // Original Repentance renders button layout only through MenuManager.
    // Native Manager cleanup destroys that menu; no persistent prompt group
    // remains in Manager to reset when a LAN game starts.
}
} // namespace
const Bindings bindings{repentance::globals::game,
                        repentance::globals::manager,
                        repentance::globals::inputManager,
                        repentance::entry::inputPressed,
                        repentance::entry::inputTriggered,
                        repentance::entry::inputValue,
                        repentance::entry::playerShootingEntity,
                        repentance::layout::manager::renderFrame,
                        repentance::layout::game::pauseMenu,
                        repentance::layout::game::players,
                        repentance::layout::inputDevice::keyboardId,
                        repentance::layout::inputDevice::firstGamepadId,
                        {repentance::layout::player::controller,
                         repentance::layout::entity::positionX,
                         repentance::layout::entity::positionY},
                        installQuery,
                        repentance::mouse_input::install,
                        nativeAction,
                        resetMenuPrompts};
} // namespace isaac::engine::native_input

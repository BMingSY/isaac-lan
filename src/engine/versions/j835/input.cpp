#include "engine/versions/common/input_bindings.h"
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
#include "engine/versions/j835/input_actions.h"
#include "engine/versions/j835/input_queries.h"
#include "engine/versions/j835/mouse_input.h"

namespace isaac::engine::native_input {
namespace {
bool installQuery(std::uintptr_t image, Detour detour, Query& original,
                  void (*)(const std::string&)) {
    return j835::input_queries::install(image, detour, original);
}
int nativeAction(int action) {
    if (action == input::action::restart)
        return j835::input_actions::restart;
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
const Bindings bindings{j835::globals::game,
                        j835::globals::manager,
                        j835::globals::inputManager,
                        j835::entry::inputPressed,
                        j835::entry::inputTriggered,
                        j835::entry::inputValue,
                        j835::entry::playerShootingEntity,
                        j835::layout::manager::renderFrame,
                        j835::layout::game::pauseMenu,
                        j835::layout::game::players,
                        j835::layout::inputDevice::keyboardId,
                        j835::layout::inputDevice::firstGamepadId,
                        {j835::layout::player::controller, j835::layout::entity::positionX,
                         j835::layout::entity::positionY},
                        installQuery,
                        j835::mouse_input::install,
                        nativeAction,
                        resetMenuPrompts};
} // namespace isaac::engine::native_input

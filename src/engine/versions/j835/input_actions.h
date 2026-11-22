#pragma once
#include "core/input_actions.h"

namespace isaac::engine::j835::input_actions {
// J835 resources/scripts/enums.lua: the first sixteen wire actions and menu
// directions match Repentance+. Restart/fullscreen/mute were reordered; emotes do not exist.
inline constexpr int restart = 16, fullscreen = 17, mute = 18;
inline constexpr int menuLeft = 20, menuRight = 21, menuUp = 22, menuDown = 23;
inline constexpr int menuLeftTrigger = 24, menuRightTrigger = 25, menuTab = 26;
inline constexpr int consoleCallback = 28;
static_assert(menuLeft == input::action::menuLeft && menuRight == input::action::menuRight &&
              menuUp == input::action::menuUp && menuDown == input::action::menuDown);
} // namespace isaac::engine::j835::input_actions

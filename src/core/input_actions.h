#pragma once
// ButtonAction IDs shared by native input and the compact input frame.
namespace isaac::input::action {
inline constexpr int moveLeft = 0, moveRight = 1, moveUp = 2, moveDown = 3;
inline constexpr int shootLeft = 4, shootRight = 5, shootUp = 6, shootDown = 7;
inline constexpr int menuPause = 12, menuConfirm = 14, menuBack = 15;
inline constexpr int emote = 30;
inline constexpr int menuLeft = 20, menuRight = 21, menuUp = 22, menuDown = 23;
} // namespace isaac::input::action

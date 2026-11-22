#pragma once
namespace isaac::engine::repentance_plus {
namespace scene {
inline constexpr int menu = 1, game = 2;
}
namespace menuPage {
inline constexpr int title = 1, save = 2, main = 3;
}
namespace mainMenuSelection {
inline constexpr int online = 2;
}
namespace menuRequest {
inline constexpr int exitGame = 2;
}
namespace fadeAction {
inline constexpr int gameOverRestart = 5, heldRestart = 6;
}
namespace pausePage {
inline constexpr int root = 1, options = 2;
}
namespace pauseSelection {
inline constexpr int resume = 0, exit = 3;
}
namespace pauseOption {
inline constexpr int controller = 1;
}
inline constexpr unsigned saveSlotCount = 3;
} // namespace isaac::engine::repentance_plus

#pragma once
namespace isaac::engine::repentance {
inline constexpr unsigned saveSlotCount = 3;
namespace menuPage {
inline constexpr int title = 1, save = 2, main = 3;
}
namespace scene {
inline constexpr int menu = 1, game = 2;
}
namespace menuRequest {
inline constexpr int exitGame = 2;
}
namespace fadeAction {
inline constexpr int gameOverRestart = 4, heldRestart = 5;
}
namespace pausePage {
inline constexpr int root = 1, options = 2;
}
namespace pauseSelection {
inline constexpr int resume = 1, exit = 2;
}
namespace pauseOption {
inline constexpr int controller = 1;
}
} // namespace isaac::engine::repentance

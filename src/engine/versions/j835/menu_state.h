#pragma once
namespace isaac::engine::j835 {
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
} // namespace isaac::engine::j835

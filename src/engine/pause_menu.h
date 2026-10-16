#pragma once
#include <cstdint>

namespace isaac::pause_menu {
enum class Intent { none, resume, exit };
struct State {
    int page = 0, selection = -1, controller = -1, optionId = -1;
};
State state(std::uintptr_t image);
void show(std::uintptr_t image);
void hide(std::uintptr_t image);
// Match actual visibility without resetting a visible menu's current subpage.
void synchronize(std::uintptr_t image, bool paused);
void controls(std::uintptr_t image);
// Decode only actions whose native effect must be coordinated by the session.
Intent intent(std::uintptr_t image, int action);
bool changesController(std::uintptr_t image, int action);
// Keep the menu's player index in the current native roster's coordinates.
void selectPlayer(std::uintptr_t image, unsigned slot);
class ViewScope {
    std::uintptr_t menu = 0;
    int previous = 0;

  public:
    ViewScope(std::uintptr_t image, unsigned slot);
    ~ViewScope();
    ViewScope(const ViewScope&) = delete;
};
} // namespace isaac::pause_menu

#include "engine/pause_menu.h"
#include "engine/versions/common/pause_bindings.h"
#include "core/input_actions.h"

namespace isaac::pause_menu {
namespace {
using Address = std::uintptr_t;
const auto& binding = engine::native_pause::bindings;
static_assert(sizeof(Address) == 4);
template <class T> T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<T*>(address + offset);
}
Address game(Address image) {
    return image ? at<Address>(image, binding.game) : 0;
}
Address menu(Address image) {
    const auto g = game(image);
    return g ? g + binding.pauseMenu : 0;
}
bool roster(Address g, Address& begin, Address& end) {
    if (!g)
        return false;
    begin = at<Address>(g, binding.players);
    end = at<Address>(g, binding.players + sizeof(Address));
    return begin && end >= begin && (end - begin) % 4 == 0 && end - begin <= 256 * 4;
}
int option(Address p) {
    const auto options = p + binding.options;
    const auto selected = at<int>(options, binding.optionSelection);
    const auto begin = at<Address>(options, binding.optionEntries),
               end = at<Address>(options, binding.optionEntries + sizeof(Address)),
               capacity = at<Address>(options, binding.optionEntries + 2 * sizeof(Address));
    if (!begin || end < begin || capacity < end || (end - begin) % 4 || end - begin > 256 * 4 ||
        selected < 0 || static_cast<unsigned>(selected) >= (end - begin) / 4)
        return -1;
    return at<int>(begin, selected * 4);
}
void call(Address image, unsigned entry) {
    if (const auto p = menu(image)) {
        using Call = void(__attribute__((thiscall))*)(void*);
        reinterpret_cast<Call>(image + entry)(reinterpret_cast<void*>(p));
    }
}
} // namespace
State state(Address image) {
    State result;
    const auto p = menu(image);
    if (!p)
        return result;
    result.page = at<int>(p);
    result.selection = at<int>(p, binding.selection);
    if (result.page == binding.optionsPage)
        result.optionId = option(p);
    Address begin, end;
    const auto index = binding.playerIndex ? at<int>(p, *binding.playerIndex) : 0;
    if (index >= 0 && roster(game(image), begin, end) &&
        static_cast<unsigned>(index) < (end - begin) / 4)
        if (const auto player = at<Address>(begin, index * 4))
            result.controller = at<int>(player, binding.playerController);
    return result;
}
void show(Address image) {
    call(image, binding.show);
}
void hide(Address image) {
    if (const auto p = menu(image); p && at<int>(p) != 0) {
        if (at<int>(p) == binding.optionsPage)
            if (const auto manager = at<Address>(image, binding.manager)) {
                // A teammate can resume while this peer is editing Options.
                // Preserve the native Back path's configuration commit.
                using Save = void(__attribute__((thiscall))*)(void*);
                reinterpret_cast<Save>(image + binding.saveOptions)(
                    reinterpret_cast<void*>(manager + binding.managerOptions));
            }
        call(image, binding.hide);
    }
}
void controls(Address image) {
    if (const auto p = menu(image); p && at<int>(p) != 0)
        call(image, binding.controls);
}
void synchronize(Address image, bool paused) {
    if ((state(image).page != 0) == paused)
        return;
    if (paused)
        show(image);
    else
        hide(image);
}
Intent intent(Address image, int action) {
    const auto p = menu(image);
    if (!p || at<int>(p) != binding.rootPage)
        return Intent::none;
    if (action == input::action::menuPause || action == input::action::menuBack)
        return Intent::resume;
    if (action == input::action::menuConfirm) {
        const auto selection = at<int>(p, binding.selection);
        if (selection == binding.resumeSelection)
            return Intent::resume;
        if (selection == binding.exitSelection)
            return Intent::exit;
    }
    return Intent::none;
}
bool changesController(Address image, int action) {
    const auto p = menu(image);
    if (!p || action != input::action::menuConfirm || at<int>(p) != binding.optionsPage)
        return false;
    const auto selected = option(p);
    return selected < 0 || selected == binding.controllerOption;
}
void selectPlayer(Address image, unsigned slot) {
    Address begin, end;
    const auto g = game(image);
    if (!binding.playerIndex || slot >= 4 || !roster(g, begin, end))
        return;
    for (auto entry = begin; entry != end; entry += 4)
        if (const auto player = at<Address>(entry);
            player && at<int>(player, binding.playerController) == static_cast<int>(slot + 1)) {
            at<int>(g + binding.pauseMenu, *binding.playerIndex) = (entry - begin) / 4;
            return;
        }
}
ViewScope::ViewScope(Address image, unsigned slot) {
    Address begin, end;
    const auto g = game(image);
    if (!binding.playerIndex || slot >= 4 || !roster(g, begin, end) || begin == end)
        return;
    const auto player = at<Address>(begin);
    if (!player || at<int>(player, binding.playerController) != static_cast<int>(slot + 1))
        return;
    menu = g + binding.pauseMenu;
    previous = at<int>(menu, *binding.playerIndex);
    at<int>(menu, *binding.playerIndex) = 0;
}
ViewScope::~ViewScope() {
    if (menu)
        at<int>(menu, *binding.playerIndex) = previous;
}
} // namespace isaac::pause_menu

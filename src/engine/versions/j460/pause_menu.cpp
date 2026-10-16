#include "engine/pause_menu.h"
#include "engine/versions/j460/entrypoints.h"

namespace isaac::pause_menu {
namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
template <class T> T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<T*>(address + offset);
}
Address game(Address image) {
    return image ? at<Address>(image, engine::j460::globals::game) : 0;
}
Address menu(Address image) {
    const auto g = game(image);
    return g ? g + 0x23a74 : 0;
}
bool roster(Address g, Address& begin, Address& end) {
    if (!g)
        return false;
    begin = at<Address>(g, 0x1baa8);
    end = at<Address>(g, 0x1baac);
    return begin && end >= begin && (end - begin) % 4 == 0 && end - begin <= 256 * 4;
}
int option(Address p) {
    const auto options = p + 0x5b0;
    const auto selected = at<int>(options, 8);
    const auto begin = at<Address>(options, 0x27c), end = at<Address>(options, 0x280),
               capacity = at<Address>(options, 0x284);
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
    result.selection = at<int>(p, 8);
    if (result.page == 2)
        result.optionId = option(p);
    Address begin, end;
    const auto index = at<int>(p, 0xfac);
    if (index >= 0 && roster(game(image), begin, end) &&
        static_cast<unsigned>(index) < (end - begin) / 4)
        if (const auto player = at<Address>(begin, index * 4))
            result.controller = at<int>(player, 0x1618);
    return result;
}
void show(Address image) {
    call(image, engine::j460::entry::pauseMenuShow);
}
void hide(Address image) {
    if (const auto p = menu(image); p && at<int>(p) != 0) {
        if (at<int>(p) == 2)
            if (const auto manager = at<Address>(image, engine::j460::globals::manager)) {
                // A teammate can resume while this peer is editing Options.
                // Preserve the native Back path's configuration commit.
                using Save = void(__attribute__((thiscall))*)(void*);
                reinterpret_cast<Save>(image + engine::j460::entry::optionsSave)(
                    reinterpret_cast<void*>(manager + 0x2a33c));
            }
        call(image, engine::j460::entry::pauseMenuHide);
    }
}
void controls(Address image) {
    if (const auto p = menu(image); p && at<int>(p) != 0)
        call(image, engine::j460::entry::pauseMenuControls);
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
    if (!p || at<int>(p) != 1)
        return Intent::none;
    if (action == 12 || action == 15)
        return Intent::resume;
    if (action == 14) {
        const auto selection = at<int>(p, 8);
        if (selection == 2)
            return Intent::resume;
        if (selection == 3)
            return Intent::exit;
    }
    return Intent::none;
}
bool changesController(Address image, int action) {
    const auto p = menu(image);
    if (!p || action != 14 || at<int>(p) != 2)
        return false;
    const auto selected = option(p);
    return selected < 0 || selected == 1;
}
void selectPlayer(Address image, unsigned slot) {
    Address begin, end;
    const auto g = game(image);
    if (slot >= 4 || !roster(g, begin, end))
        return;
    for (auto entry = begin; entry != end; entry += 4)
        if (const auto player = at<Address>(entry);
            player && at<int>(player, 0x1618) == static_cast<int>(slot + 1)) {
            at<int>(g + 0x23a74, 0xfac) = (entry - begin) / 4;
            return;
        }
}
ViewScope::ViewScope(Address image, unsigned slot) {
    Address begin, end;
    const auto g = game(image);
    if (slot >= 4 || !roster(g, begin, end) || begin == end)
        return;
    const auto player = at<Address>(begin);
    if (!player || at<int>(player, 0x1618) != static_cast<int>(slot + 1))
        return;
    menu = g + 0x23a74;
    previous = at<int>(menu, 0xfac);
    at<int>(menu, 0xfac) = 0;
}
ViewScope::~ViewScope() {
    if (menu)
        at<int>(menu, 0xfac) = previous;
}
} // namespace isaac::pause_menu

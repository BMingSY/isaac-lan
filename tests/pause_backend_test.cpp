#include "test_support.h"
#include "engine/pause_menu.h"
#include "core/input_actions.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#else
#include "engine/versions/j510/entrypoints.h"
#endif
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <array>
#include <cstring>
#include <vector>

namespace {
namespace menu = isaac::pause_menu;
namespace action = isaac::input::action;
#ifdef ISAAC_LAN_TEST_J835
namespace backend = isaac::engine::j835;
constexpr unsigned pauseOffset = 0x10203c, optionsOffset = 0x806a8;
constexpr unsigned optionsSelection = 4, optionsEntries = 0x260;
constexpr unsigned playersOffset = 0x1ba50, controllerOffset = 0x154c;
constexpr unsigned managerOptions = 0x29df8;
constexpr int resumeSelection = 1, exitSelection = 2;
#else
namespace backend = isaac::engine::j510;
constexpr unsigned pauseOffset = 0x23a7c, optionsOffset = 0x5b0;
constexpr unsigned optionsSelection = 8, optionsEntries = 0x27c;
constexpr unsigned playersOffset = 0x1baa8, controllerOffset = 0x161c;
constexpr unsigned managerOptions = 0x2a614;
constexpr int resumeSelection = 2, exitSelection = 3;
#endif
using Address = std::uintptr_t;
constexpr unsigned imageSize = privateGameImageBytes;
unsigned char* image;
std::vector<unsigned char> game(0x190000), manager(0x2a500);
std::array<std::array<unsigned char, 0x2200>, 4> players{};
std::array<Address, 4> roster;
std::array<int, 4> options{5, 4, 1, 7};
std::vector<char> calls;
template <class T> T& field(void* object, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address base() {
    return reinterpret_cast<Address>(image);
}
void* pause() {
    return game.data() + pauseOffset;
}
void* settings() {
    return game.data() + pauseOffset + optionsOffset;
}
int& page() {
    return field<int>(pause());
}
int& selection() {
    return field<int>(pause(), 8);
}
void __attribute__((thiscall)) show(void* receiver) {
    require(receiver == pause(), "Pause show receiver");
    calls.push_back('S');
    page() = 1;
    selection() = resumeSelection;
}
void __attribute__((thiscall)) hide(void* receiver) {
    require(receiver == pause(), "Pause hide receiver");
    calls.push_back('H');
    // Only native update/animation owns the eventual state change.
}
void __attribute__((thiscall)) controls(void* receiver) {
    require(receiver == pause(), "Pause controls receiver");
    calls.push_back('C');
}
void __attribute__((thiscall)) save(void* receiver) {
    require(receiver == manager.data() + managerOptions && page() == 2,
            "Options must be saved from the correct subobject before native hide");
    calls.push_back('O');
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    field<std::uint32_t>(image, rva + 1) =
        static_cast<std::uint32_t>(reinterpret_cast<Address>(fn) - base() - rva - 5);
}
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image, "Allocate isolated pause image");
    patch(backend::entry::pauseMenuShow, show);
    patch(backend::entry::pauseMenuHide, hide);
    patch(backend::entry::pauseMenuControls, controls);
    patch(backend::entry::optionsSave, save);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(image, backend::globals::manager) = reinterpret_cast<Address>(manager.data());
    for (unsigned i = 0; i < players.size(); ++i) {
        roster[i] = reinterpret_cast<Address>(players[i].data());
        field<int>(players[i].data(), controllerOffset) = i + 1;
    }
    field<Address>(game.data(), playersOffset) = reinterpret_cast<Address>(roster.data());
    field<Address>(game.data(), playersOffset + 4) = reinterpret_cast<Address>(roster.data() + 4);
    field<Address>(settings(), optionsEntries) = reinterpret_cast<Address>(options.data());
    field<Address>(settings(), optionsEntries + 4) = reinterpret_cast<Address>(options.data() + 4);
    field<Address>(settings(), optionsEntries + 8) = reinterpret_cast<Address>(options.data() + 4);
}
void nativeCalls() {
    require(menu::state(0).controller == -1, "Missing image must be inert");
    menu::show(0);
    menu::hide(0);
    menu::controls(0);
    menu::controls(base());
    menu::hide(base());
    require(calls.empty(), "Hidden menu or missing image invoked native code");
    menu::synchronize(base(), true);
    require(calls == std::vector<char>{'S'} && page() == 1,
            "Opening a pause menu must use the native show method");
    selection() = exitSelection;
    menu::synchronize(base(), true);
    require(calls.size() == 1 && selection() == exitSelection,
            "Repeated paused state reset native selection");
    menu::controls(base());
    require(calls.back() == 'C', "Native controls were not forwarded");
    calls.clear();
    page() = 2;
    menu::synchronize(base(), true);
    require(calls.empty() && page() == 2, "Paused synchronization reset the options subpage");
    menu::synchronize(base(), false);
    require(calls == std::vector<char>({'O', 'H'}) && page() == 2,
            "Resume must preserve native options save/hide order and animation ownership");
    page() = 0;
    calls.clear();
    menu::synchronize(base(), false);
    require(calls.empty(), "Repeated resumed state called hidden native menu");
}
void intentsAndOptions() {
    for (int p : {0, 1, 2, 3}) {
        page() = p;
        for (int s = 0; s < 5; ++s) {
            selection() = s;
            const auto expected = p != 1                 ? menu::Intent::none
                                  : s == resumeSelection ? menu::Intent::resume
                                  : s == exitSelection   ? menu::Intent::exit
                                                         : menu::Intent::none;
            require(menu::intent(base(), action::menuConfirm) == expected,
                    "Root selection decoded with the wrong version's numbering");
            for (const auto back : {action::menuPause, action::menuBack})
                require(menu::intent(base(), back) ==
                            (p == 1 ? menu::Intent::resume : menu::Intent::none),
                        "A submenu's local back action escaped into session resume");
        }
    }
    page() = 2;
    for (int s = 0; s < 4; ++s) {
        field<int>(settings(), optionsSelection) = s;
        require(menu::state(base()).optionId == options[s] &&
                    menu::changesController(base(), action::menuConfirm) == (s == 2),
                "Options must follow native entry IDs, not selection indices");
        require(!menu::changesController(base(), action::menuBack),
                "Back changed controller selection");
    }
    for (int invalid : {-1, 4, 100}) {
        field<int>(settings(), optionsSelection) = invalid;
        require(menu::state(base()).optionId == -1 &&
                    menu::changesController(base(), action::menuConfirm),
                "Invalid native option selection was dereferenced or permitted");
    }
    field<int>(settings(), optionsSelection) = 0;
    field<Address>(settings(), optionsEntries + 8) = reinterpret_cast<Address>(options.data());
    require(menu::state(base()).optionId == -1, "Native option vector escaped capacity bounds");
}
void playerView() {
#ifdef ISAAC_LAN_TEST_J835
    const auto before = game;
    menu::selectPlayer(base(), 1);
    { menu::ViewScope view(base(), 1); }
    require(game == before && menu::state(base()).controller == 1,
            "Original Repentance must not invent a native pause-player index");
#else
    menu::selectPlayer(base(), 1);
    require(menu::state(base()).controller == 2,
            "Plus pause selection did not follow controller identity");
    field<int>(pause(), 0xfb4) = 0;
#endif
    // The room view lends a reordered roster with the local actor first.
    std::swap(roster[0], roster[1]);
    {
        menu::ViewScope view(base(), 1);
        require(menu::state(base()).controller == 2,
                "Pause view did not follow the borrowed roster");
        { menu::ViewScope nested(base(), 1); }
        require(menu::state(base()).controller == 2, "Nested pause view lost its local actor");
    }
    std::swap(roster[0], roster[1]);
    require(menu::state(base()).controller == 1, "Pause view retained another room's actor");
    field<Address>(game.data(), playersOffset + 4) = reinterpret_cast<Address>(roster.data()) + 1;
    require(menu::state(base()).controller == -1, "Invalid native roster was traversed");
    field<Address>(image, backend::globals::game) = 0;
    require(menu::state(base()).controller == -1, "Destroyed game retained a borrowed actor");
}
} // namespace
int main() {
    setup();
    nativeCalls();
    intentsAndOptions();
    playerView();
    require(VirtualFree(image, 0, MEM_RELEASE), "Release isolated pause fixture");
}

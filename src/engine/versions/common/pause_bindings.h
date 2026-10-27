#pragma once
#include <cstdint>
#include <optional>

namespace isaac::engine::native_pause {
// Both versions expose the same synchronous menu calls, with different native
// subobjects and root selections. J835 derives its player from roster[0].
struct Bindings {
    std::uint32_t game, manager, show, hide, controls, saveOptions;
    unsigned pauseMenu, players, playerController, managerOptions;
    unsigned selection, options, optionSelection, optionEntries;
    std::optional<unsigned> playerIndex;
    int rootPage, optionsPage, resumeSelection, exitSelection, controllerOption;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_pause

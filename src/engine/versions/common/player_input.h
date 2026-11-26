#pragma once
#include <cstdint>
#include <optional>

namespace isaac::engine::native_players {
// Private backend calls. Game owns players, companions and the roster; these
// operations borrow them synchronously and never allocate/free native storage.
struct Bindings {
    std::uint32_t game, spawn, assign, initialize, getHUD, assignHUDs;
    unsigned manager, players, controller, positionX, positionY, previousX, previousY, initSeed,
        parent, twin, lazarusBackup;
};
extern const Bindings bindings;
bool assign(std::uintptr_t image, unsigned slot, int controller);
// Initialization may append companion actors and reallocate the native vector.
// onInitialized runs after native inventory/stat initialization, before placing
// all new bodies and assigning HUDs. Failure does not undo a native spawn.
std::optional<unsigned> spawn(std::uintptr_t image, int type, int controller,
                              void (*onInitialized)(void*, unsigned));
} // namespace isaac::engine::native_players

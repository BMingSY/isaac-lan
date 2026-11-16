#pragma once
#include "engine/versions/common/progress.h"

namespace isaac::engine::native_session {
// Private native bindings. Public session callbacks retain no game addresses.
// Start entries consume a 0x5c-byte Seeds value and pop 0x68 stack bytes. J835
// ignores ECX at these entries; J460 receives the object in ECX.
struct Entries {
    std::uint32_t save, deleteSave, saveRerun, executeMenu, serializeProgress;
    std::uint32_t start, executeStart, update, consoleUpdate, consoleCommand, consolePrint,
        controls;
    std::uint32_t capture, clear, resetPause, stringAssign, stringDestroy;
    std::uint32_t parseSeed, constructSeeds, setSeed, startNew;
};
struct Manager {
    unsigned scene, saveSlot, progress, saveState, continueAvailable, continueRequested;
    unsigned deleteSaveRequested, cinematicActive, menuRequested, requestedMenu;
};
struct Game {
    unsigned pauseMenu, console, stage, stageType, floorSeeds, stateFlags;
    unsigned fadeAction, fadeAlpha, restartHeldFrames;
};
// Version-owned call/branch adapters observe native-eligible awards. The session
// component owns installation and rollback with its other lifecycle hooks.
struct CompletionHook {
    unsigned target;
    void* detour;
    void** original;
};
extern const CompletionHook completionHook;
void observeCompletion(unsigned event, unsigned character, unsigned difficulty) noexcept;
struct Bindings {
    std::uint32_t manager, game;
    Entries entry;
    Manager managerLayout;
    Game gameLayout;
    native_progress::Layout progress;
    unsigned progressReadOnly, consoleState;
    int gameScene, exitMenu, gameOverRestart, heldRestart;
    // Persistence uses each version's native file/cloud selection and ownership.
    void (*persistProgress)(std::uintptr_t image, std::uintptr_t progress);
    unsigned completionDefinitions = 0;
    unsigned progressTryUnlock = 0, progressIncreaseCounter = 0;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_session

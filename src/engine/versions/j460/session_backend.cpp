#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"
#include "engine/versions/common/session_bindings.h"

namespace isaac::engine::native_session {
namespace {
namespace backend = j460;
namespace layout = backend::layout;
void persistProgress(std::uintptr_t image, std::uintptr_t progress) {
    using Method = void(__attribute__((thiscall))*)(void*);
    auto* object = reinterpret_cast<void*>(progress);
    reinterpret_cast<Method>(image + j460::entry::progressSaveCloud)(object);
    reinterpret_cast<Method>(image + j460::entry::progressSaveFile)(object);
}
} // namespace
constinit const Bindings bindings{
    .manager = backend::globals::manager,
    .game = backend::globals::game,
    .entry =
        {
            .save = backend::entry::managerSave,
            .deleteSave = backend::entry::managerDeleteSave,
            .saveRerun = backend::entry::managerSaveRerun,
            .executeMenu = backend::entry::managerExecuteMenu,
            .serializeProgress = backend::entry::progressSerialize,
            .start = backend::entry::gameStart,
            .executeStart = backend::entry::managerExecuteStart,
            .update = backend::entry::gameUpdate,
            .consoleUpdate = backend::entry::consoleUpdate,
            .consoleCommand = backend::entry::consoleRunCommand,
            .consolePrint = backend::entry::consolePrint,
            .controls = backend::entry::gameControls,
            .capture = backend::entry::runtimeNetCapture,
            .clear = backend::entry::runtimeNetClear,
            .resetPause = backend::entry::runtimeNetExecuteStart,
            .stringAssign = backend::entry::frontendAssign,
            .stringDestroy = backend::entry::frontendMenuUpdate,
            .parseSeed = backend::entry::runtimeNetParseSeed,
            .constructSeeds = backend::entry::runtimeNetSeedConstructor,
            .setSeed = backend::entry::runtimeNetSetSeed,
            .startNew = backend::entry::runtimeNetStartGame,
        },
    .managerLayout =
        {
            .scene = layout::manager::scene,
            .saveSlot = layout::manager::saveSlot,
            .progress = layout::manager::progress,
            .saveState = layout::manager::saveState,
            .continueAvailable = layout::manager::continueAvailable,
            .continueRequested = layout::manager::continueRequested,
            .deleteSaveRequested = layout::manager::deleteSaveRequested,
            .cinematicActive = layout::manager::cinematicActive,
            .menuRequested = layout::manager::menuRequested,
            .requestedMenu = layout::manager::requestedMenu,
        },
    .gameLayout =
        {
            .pauseMenu = layout::game::pauseMenu,
            .console = layout::game::console,
            .stage = layout::game::stage,
            .stageType = layout::game::stageType,
            .floorSeeds = layout::game::floorSeeds,
            .stateFlags = layout::game::stateFlags,
            .fadeAction = layout::game::fadeAction,
            .fadeAlpha = layout::game::fadeAlpha,
            .restartHeldFrames = layout::game::restartHeldFrames,
        },
    .progress = layout::progress::fields,
    .progressReadOnly = layout::progress::readOnly,
    .consoleState = layout::console::state,
    .gameScene = backend::scene::game,
    .exitMenu = backend::menuRequest::exitGame,
    .gameOverRestart = backend::fadeAction::gameOverRestart,
    .heldRestart = backend::fadeAction::heldRestart,
    .persistProgress = persistProgress,
};
} // namespace isaac::engine::native_session

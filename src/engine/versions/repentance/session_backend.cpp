#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "engine/versions/repentance/menu_state.h"
#include "engine/versions/common/session_bindings.h"
#include "engine/versions/common/branch_frame.h"

namespace isaac::engine::native_session {
namespace {
namespace backend = repentance;
namespace layout = backend::layout;
void* originalRecordCompletion;
void persistProgress(std::uintptr_t image, std::uintptr_t progress) {
    using Flush = void(__attribute__((thiscall))*)(void*, bool);
    *reinterpret_cast<bool*>(progress + repentance::layout::progress::dirty) = true;
    // The native flush checks initialization, writes its dated backup, then
    // chooses Steam or the local file according to the actual game settings.
    reinterpret_cast<Flush>(image + repentance::entry::progressPersist)(
        reinterpret_cast<void*>(progress), true);
}
} // namespace
extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_repentance_completion_prepare(
    std::uintptr_t* registers) noexcept {
    // Native RecordPlayerCompletion has already excluded ghosts, dependent
    // bodies and duplicate twins, and selected EBX's descriptor in ECX.
    enum Register : unsigned { game = 0, event = 1, character = 4, continuation = 9 };
    registers[continuation] = reinterpret_cast<std::uintptr_t>(originalRecordCompletion);
    const auto difficulty =
        *reinterpret_cast<const unsigned*>(registers[game] + layout::game::difficulty);
    observeCompletion(registers[event], registers[character], difficulty);
}
__attribute__((naked)) void isaac_lan_repentance_completion() {
    __asm__ __volatile__(ISAAC_LAN_NATIVE_BRANCH_SAVE
                         "pushl %eax\n\tcall _isaac_lan_repentance_completion_prepare\n\taddl $4, "
                         "%esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE);
}
}
const CompletionHook completionHook{backend::entry::recordCompletionBoundary,
                                    reinterpret_cast<void*>(isaac_lan_repentance_completion),
                                    &originalRecordCompletion};
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
            .deleteSlotFile = backend::entry::gameStateDeleteFile,
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
            .soloDiskChecksum = layout::manager::saveChecksum,
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
    .completionDefinitions = backend::globals::completionDefinitions,
    .progressTryUnlock = backend::entry::progressTryUnlock,
    .progressIncreaseCounter = backend::entry::progressIncreaseCounter,
};
} // namespace isaac::engine::native_session

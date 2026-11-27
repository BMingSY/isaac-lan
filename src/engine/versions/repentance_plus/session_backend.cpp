#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
#include "engine/versions/repentance_plus/menu_state.h"
#include "engine/versions/common/session_bindings.h"

namespace isaac::engine::native_session {
namespace {
namespace backend = repentance_plus;
namespace layout = backend::layout;
void enableCrimeMode(std::uintptr_t image, void* seeds) {
    constexpr int crimeModeEffect = 80; // V1CE BSMT in the native seed menu.
    using AddSeedEffect = void(__attribute__((thiscall))*)(void*, int);
    reinterpret_cast<AddSeedEffect>(image + backend::entry::addSeedEffect)(seeds, crimeModeEffect);
}
using RecordCompletion = void(__stdcall*)(unsigned, unsigned, unsigned);
RecordCompletion originalRecordCompletion;
void __stdcall recordCompletion(unsigned event, unsigned character, unsigned difficulty) {
    originalRecordCompletion(event, character, difficulty);
    observeCompletion(event, character, difficulty);
}
// The caller owns this reference and releases it after dispatch, even when the
// game could not resolve the Steam lobby to one of its own lobby objects.
struct LobbyReference {
    const void* vtable;
    const void* lobby;
    const void* owner;
};
static_assert(offsetof(LobbyReference, lobby) == 4 && sizeof(LobbyReference) == 12);
using MemberChange = void(__stdcall*)(const LobbyReference*, const std::uint64_t*, unsigned);
MemberChange originalMemberChange;
void __stdcall memberChange(const LobbyReference* reference, const std::uint64_t* member,
                            unsigned change) {
    if (reference && reference->lobby)
        originalMemberChange(reference, member, change);
}
void persistProgress(std::uintptr_t image, std::uintptr_t progress) {
    using Method = void(__attribute__((thiscall))*)(void*);
    auto* object = reinterpret_cast<void*>(progress);
    reinterpret_cast<Method>(image + repentance_plus::entry::progressSaveCloud)(object);
    reinterpret_cast<Method>(image + repentance_plus::entry::progressSaveFile)(object);
}
} // namespace
bool addVersionHooks(std::uintptr_t image, SessionHooks& hooks) {
    return hooks.add(image + backend::entry::recordCharacterCompletion, recordCompletion,
                     originalRecordCompletion) &&
           hooks.add(image + backend::entry::officialLobbyMemberChange, memberChange,
                     originalMemberChange);
}
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
    .completionDefinitions = backend::globals::completionDefinitions,
    .progressTryUnlock = backend::entry::progressTryUnlock,
    .progressIncreaseCounter = backend::entry::progressIncreaseCounter,
    .enableCrimeMode = enableCrimeMode,
};
} // namespace isaac::engine::native_session

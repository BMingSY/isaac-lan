#include "engine/session_backend.h"
#include "engine/floor_generation.h"
#include "engine/rooms.h"
#include "engine/versions/common/room_hooks.h"
#include "core/chat.h"
#include "engine/versions/common/session_bindings.h"
#include "engine/versions/common/completion_marks.h"
#include <MinHook.h>
#include <cstring>

namespace isaac::engine::session {
namespace {
const auto& binding = native_session::bindings;
namespace nativeString {
inline constexpr unsigned size = 0x10, capacity = 0x14;
inline constexpr unsigned inlineBytes = 0x10, inlineCapacity = 0xf;
} // namespace nativeString
std::uintptr_t image;
bool installed;
Callbacks callbacks;
template <class T> T& at(std::uintptr_t base, unsigned offset = 0) {
    return *reinterpret_cast<T*>(base + offset);
}
std::uintptr_t manager() {
    return at<std::uintptr_t>(image, binding.manager);
}
std::uintptr_t game() {
    return at<std::uintptr_t>(image, binding.game);
}
using Plain = void(__cdecl*)();
using Method = void(__attribute__((thiscall)) *)(void*);
Plain originalSave, originalDelete, originalRerun, originalControls;
Method originalSerialize, originalExecuteStart, originalUpdate, originalConsoleUpdate, originalMenu;
struct Seeds {
    static constexpr unsigned wordCount = 23;
    std::array<std::uint32_t, wordCount> words;
};
static_assert(sizeof(Seeds) == 0x5c);
using Start = void(__attribute__((thiscall)) *)(void*, int, int, Seeds, unsigned);
Start originalStart;
using Console = void(__attribute__((thiscall)) *)(void*, const void*, bool, void*);
Console originalConsole;
using ConsolePrint = void(__attribute__((thiscall)) *)(void*, const void*, unsigned, unsigned);
ConsolePrint originalConsolePrint;
using RecordCompletion = void(__stdcall*)(unsigned, unsigned, unsigned);
RecordCompletion originalRecordCompletion;
void __stdcall recordCompletionHook(unsigned event, unsigned character, unsigned difficulty) {
    originalRecordCompletion(event, character, difficulty);
    namespace completion = native_completion;
    // The native caller has already checked run eligibility. This observer
    // never unlocks anything or changes its result, including repeated wins.
    if (!callbacks.completionAward || event >= completion::eventCount ||
        character >= completion::counters.size() || difficulty > 3 ||
        at<bool>(manager() + binding.managerLayout.progress, binding.progressReadOnly))
        return;
    const auto& award = reinterpret_cast<const completion::CharacterAwards*>(
        image + binding.completionDefinitions)[character][event];
    const bool hard = difficulty == 1 || difficulty == 3;
    callbacks.completionAward(award.counter, hard ? completion::hardBits : completion::normalBits,
                              event != completion::heartEvent || hard ? award.achievement : 0);
}
std::string* capturedOutput = nullptr;
std::string_view nativeText(const void* value) {
    const auto address = reinterpret_cast<std::uintptr_t>(value);
    const auto size = at<unsigned>(address, nativeString::size);
    const auto capacity = at<unsigned>(address, nativeString::capacity);
    const auto data = capacity <= nativeString::inlineCapacity ? static_cast<const char*>(value)
                                                               : at<const char*>(address);
    return {data, size};
}
void __attribute__((fastcall)) consolePrintHook(void* object, void*, const void* text,
                                                unsigned color, unsigned fade) {
    if (capturedOutput && capturedOutput->size() < chat::maxOutputBytes) {
        auto value = nativeText(text);
        capturedOutput->append(
            chat::boundedOutput(value, chat::maxOutputBytes - capturedOutput->size()));
    }
    originalConsolePrint(object, text, color, fade);
}

void __cdecl saveHook() {
    callbacks.save(originalSave);
}
void __cdecl deleteHook() {
    callbacks.deleteSave(originalDelete);
}
void __cdecl rerunHook() {
    callbacks.saveRerun(originalRerun);
}
void redirectRestart() {
    const auto gameOverRestart = binding.gameOverRestart, heldRestart = binding.heldRestart;
    if (!gameReady())
        return;
    const auto action = at<int>(game(), binding.gameLayout.fadeAction);
    if ((action == gameOverRestart || action == heldRestart) &&
        callbacks.restartRequest(action == heldRestart)) {
        // Consume the intent before Game::Update advances its fade into Exit.
        at<int>(game(), binding.gameLayout.fadeAction) = 0;
        at<float>(game(), binding.gameLayout.fadeAlpha) = 0;
        at<unsigned char>(game(), binding.gameLayout.restartHeldFrames) = 0;
    }
}
void __cdecl controlsHook() {
    callbacks.controls(originalControls);
    redirectRestart();
}
void __attribute__((fastcall)) serializeHook(void* object, void*) {
    auto original = [=] { originalSerialize(object); };
    if (reinterpret_cast<std::uintptr_t>(object) == manager() + binding.managerLayout.progress)
        callbacks.serializeProgress(original);
    else
        original();
}
void __attribute__((fastcall)) executeStartHook(void* object, void*) {
    callbacks.executeStart([=] { originalExecuteStart(object); });
}
void __attribute__((fastcall)) updateHook(void* object, void*) {
    callbacks.update([=] { originalUpdate(object); });
}
void __attribute__((fastcall)) consoleUpdateHook(void* object, void*) {
    callbacks.consoleUpdate([=] { originalConsoleUpdate(object); });
}
void __attribute__((fastcall)) menuHook(void* object, void*) {
    callbacks.executeMenu([=] { originalMenu(object); });
}
void __attribute__((fastcall)) startHook(void* object, void*, int type, int challenge, Seeds seeds,
                                         unsigned difficulty) {
    // Native code consumes the by-value Seeds once; this forwarding POD has no destructor.
    callbacks.start([=] { originalStart(object, type, challenge, seeds, difficulty); });
}
void __attribute__((fastcall)) consoleHook(void* object, void*, const void* text, bool silent,
                                           void* player) {
    const auto address = reinterpret_cast<std::uintptr_t>(text);
    const auto size = at<unsigned>(address, nativeString::size),
               capacity = at<unsigned>(address, nativeString::capacity);
    const auto data = capacity <= nativeString::inlineCapacity ? static_cast<const char*>(text)
                                                               : at<const char*>(address);
    callbacks.consoleCommand({data, size}, [=] { originalConsole(object, text, silent, player); });
}
} // namespace
bool install(std::uintptr_t base, const Callbacks& handlers) {
    if (!base || installed)
        return false;
    image = base;
    callbacks = handlers;
    std::array<void*, 13> targets{};
    unsigned count = 0;
    auto hook = [&](std::uintptr_t target, auto replacement, auto& original) {
        auto* address = reinterpret_cast<void*>(target);
        if (MH_CreateHook(address, reinterpret_cast<void*>(replacement),
                          reinterpret_cast<void**>(&original)) != MH_OK)
            return false;
        targets[count++] = address;
        return true;
    };
    bool success =
        installFloorGeneration(image, callbacks.largeFloor) &&
        hook(image + binding.entry.save, saveHook, originalSave) &&
        hook(image + binding.entry.deleteSave, deleteHook, originalDelete) &&
        hook(image + binding.entry.saveRerun, rerunHook, originalRerun) &&
        hook(image + binding.entry.executeMenu, menuHook, originalMenu) &&
        hook(image + binding.entry.serializeProgress, serializeHook, originalSerialize) &&
        (!binding.recordCompletion ||
         hook(image + binding.recordCompletion, recordCompletionHook, originalRecordCompletion)) &&
        hook(image + binding.entry.start, startHook, originalStart) &&
        hook(image + binding.entry.executeStart, executeStartHook, originalExecuteStart) &&
        hook(image + binding.entry.update, updateHook, originalUpdate) &&
        hook(image + binding.entry.consoleUpdate, consoleUpdateHook, originalConsoleUpdate) &&
        hook(image + binding.entry.consoleCommand, consoleHook, originalConsole) &&
        hook(image + binding.entry.consolePrint, consolePrintHook, originalConsolePrint) &&
        hook(image + binding.entry.controls, controlsHook, originalControls);
    if (success) {
        for (unsigned i = 0; i < count; ++i) {
            auto* target = targets[i];
            if (MH_EnableHook(target) != MH_OK) {
                success = false;
                break;
            }
        }
    }
    if (!success) {
        // Remove only this component's hooks, including ones already enabled.
        while (count)
            MH_RemoveHook(targets[--count]);
        callbacks = {};
        image = 0;
        return false;
    }
    installed = true;
    return true;
}
bool managerReady() {
    return image && manager();
}
bool gameReady() {
    return image && game();
}
bool continueAvailable() {
    return at<bool>(manager(), binding.managerLayout.continueAvailable);
}
void continueAvailable(bool value) {
    at<bool>(manager(), binding.managerLayout.continueAvailable) = value;
}
unsigned saveSlot() {
    return at<unsigned>(manager(), binding.managerLayout.saveSlot);
}
void captureSave() {
    using Capture = void(__attribute__((thiscall))*)(void*, void*);
    reinterpret_cast<Capture>(image + binding.entry.capture)(
        reinterpret_cast<void*>(game()),
        reinterpret_cast<void*>(manager() + binding.managerLayout.saveState));
}
void suppressDelete() {
    at<bool>(manager(), binding.managerLayout.deleteSaveRequested) = false;
}
void clearSave() {
    reinterpret_cast<Method>(image + binding.entry.clear)(
        reinterpret_cast<void*>(manager() + binding.managerLayout.saveState));
}
lan::Progress readProgress() {
    return native_progress::read(manager() + binding.managerLayout.progress, binding.progress);
}
void writeProgress(const lan::Progress& value) {
    native_progress::write(manager() + binding.managerLayout.progress, binding.progress, value);
}
std::span<const bool> progressBitCounters() {
    return native_completion::bitCounters;
}
void commitProgress(const lan::Progress& previous, const lan::Progress& value) {
    struct Writable {
        bool& flag;
        bool previous;
        explicit Writable(bool& flag) : flag(flag), previous(flag) {
            flag = false;
        }
        ~Writable() {
            flag = previous;
        }
    } writable(at<bool>(manager() + binding.managerLayout.progress, binding.progressReadOnly));
    auto personal = value;
    personal.achievements = previous.achievements;
    writeProgress(personal);
    auto progress = reinterpret_cast<void*>(manager() + binding.managerLayout.progress);
    using Unlock = bool(__attribute__((thiscall))*)(void*, unsigned);
    for (unsigned id = 1; id < value.achievements.size(); ++id)
        if (value.achievements[id] && !previous.achievements[id])
            reinterpret_cast<Unlock>(image + binding.progressTryUnlock)(progress, id);
    using Increase = void(__attribute__((thiscall))*)(void*, unsigned, int);
    reinterpret_cast<Increase>(image + binding.progressIncreaseCounter)(progress, 0, 0);
}
void persistProgress() {
    binding.persistProgress(image, manager() + binding.managerLayout.progress);
}
ProgressReadOnlyScope::ProgressReadOnlyScope()
    : previous(at<bool>(manager() + binding.managerLayout.progress, binding.progressReadOnly)) {
    at<bool>(manager() + binding.managerLayout.progress, binding.progressReadOnly) = true;
}
ProgressReadOnlyScope::~ProgressReadOnlyScope() {
    at<bool>(manager() + binding.managerLayout.progress, binding.progressReadOnly) = previous;
}
int pause() {
    return gameReady() ? at<int>(game(), binding.gameLayout.pauseMenu) : 0;
}
int scene() {
    return managerReady() ? at<int>(manager(), binding.managerLayout.scene) : -1;
}
bool cinematicFinished() {
    return !at<bool>(manager(), binding.managerLayout.cinematicActive) &&
           scene() == binding.gameScene;
}
bool exitRequested() {
    return at<bool>(manager(), binding.managerLayout.menuRequested) &&
           at<int>(manager(), binding.managerLayout.requestedMenu) == binding.exitMenu;
}
void cancelExit() {
    at<bool>(manager(), binding.managerLayout.menuRequested) = false;
}
void resetPause() {
    reinterpret_cast<Method>(image + binding.entry.resetPause)(
        reinterpret_cast<void*>(game() + binding.gameLayout.pauseMenu));
}
void pollConsole() {
    if (gameReady() && originalConsoleUpdate)
        originalConsoleUpdate(reinterpret_cast<void*>(game() + binding.gameLayout.console));
}
void hideConsole() {
    if (gameReady())
        at<int>(game() + binding.gameLayout.console, binding.consoleState) = 0;
}
std::string executeConsole(std::string_view command) {
    // MSVC owns this string's storage. Allocate and release through the same
    // native helpers used by the existing menu editor, never the MinGW heap.
    struct NativeString {
        std::array<unsigned char, nativeString::size + 2 * sizeof(unsigned)> bytes{};
        ~NativeString() {
            reinterpret_cast<Method>(image + binding.entry.stringDestroy)(this);
        }
    } text;
    at<unsigned>(reinterpret_cast<std::uintptr_t>(&text), nativeString::capacity) =
        nativeString::inlineCapacity;
    using Assign = void*(__attribute__((thiscall))*)(void*, const char*, std::size_t);
    reinterpret_cast<Assign>(image + binding.entry.stringAssign)(&text, command.data(),
                                                                 command.size());
    std::string output;
    struct Capture {
        std::string* previous = capturedOutput;
        explicit Capture(std::string& output) {
            capturedOutput = &output;
        }
        ~Capture() {
            capturedOutput = previous;
        }
    } capture(output);
    originalConsole(reinterpret_cast<void*>(game() + binding.gameLayout.console), &text, false,
                    reinterpret_cast<void*>(rooms::presentationPlayer()));
    return output;
}
void controls() {
    originalControls();
    redirectRestart();
}
std::uint32_t parseSeed(std::string_view text) {
    constexpr unsigned seedGroupLength = 4;
    struct SmallString {
        char text[nativeString::inlineBytes]{};
        unsigned size = seedGroupLength * 2 + 1, capacity = nativeString::inlineCapacity;
    } value;
    if (text.size() != seedGroupLength * 2)
        return 0;
    std::memcpy(value.text, text.data(), seedGroupLength);
    value.text[seedGroupLength] = ' ';
    std::memcpy(value.text + seedGroupLength + 1, text.data() + seedGroupLength, seedGroupLength);
    using Parse = std::uint32_t(__cdecl*)(const SmallString*);
    return reinterpret_cast<Parse>(image + binding.entry.parseSeed)(&value);
}
void start(std::uint32_t seed, int character, unsigned difficulty) {
    Seeds seeds{};
    using Set = void(__attribute__((thiscall))*)(void*, std::uint32_t);
    reinterpret_cast<Method>(image + binding.entry.constructSeeds)(&seeds);
    reinterpret_cast<Set>(image + binding.entry.setSeed)(&seeds, seed);
    reinterpret_cast<Start>(image + binding.entry.startNew)(reinterpret_cast<void*>(manager()),
                                                            character, 0, seeds, difficulty);
}
void requestContinue() {
    at<bool>(manager(), binding.managerLayout.continueRequested) = true;
}
lan::Stage stage() {
    lan::Stage value;
    value.level = at<int>(game(), binding.gameLayout.stage);
    value.type = at<int>(game(), binding.gameLayout.stageType);
    std::memcpy(value.seeds.data(), reinterpret_cast<void*>(game() + binding.gameLayout.floorSeeds),
                sizeof(value.seeds));
    std::memcpy(value.stateFlags.data(),
                reinterpret_cast<void*>(game() + binding.gameLayout.stateFlags),
                sizeof(value.stateFlags));
    return value;
}
void applyStage(const lan::Stage& value) {
    std::memcpy(reinterpret_cast<void*>(game() + binding.gameLayout.floorSeeds), value.seeds.data(),
                sizeof(value.seeds));
    std::memcpy(reinterpret_cast<void*>(game() + binding.gameLayout.stateFlags),
                value.stateFlags.data(), sizeof(value.stateFlags));
}
} // namespace isaac::engine::session

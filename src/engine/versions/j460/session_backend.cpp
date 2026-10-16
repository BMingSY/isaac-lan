#include "engine/session_backend.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/menu_state.h"
#include <MinHook.h>
#include <cstring>

namespace isaac::engine::session {
namespace {
namespace layout = j460::layout;
std::uintptr_t image;
Callbacks callbacks;
template <class T> T& at(std::uintptr_t base, unsigned offset = 0) {
    return *reinterpret_cast<T*>(base + offset);
}
std::uintptr_t manager() {
    return at<std::uintptr_t>(image, j460::globals::manager);
}
std::uintptr_t game() {
    return at<std::uintptr_t>(image, j460::globals::game);
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
void __cdecl saveHook() {
    callbacks.save(originalSave);
}
void __cdecl deleteHook() {
    callbacks.deleteSave(originalDelete);
}
void __cdecl rerunHook() {
    callbacks.saveRerun(originalRerun);
}
void __cdecl controlsHook() {
    callbacks.controls(originalControls);
}
void __attribute__((fastcall)) serializeHook(void* object, void*) {
    auto original = [=] { originalSerialize(object); };
    if (reinterpret_cast<std::uintptr_t>(object) == manager() + layout::manager::progress)
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
    // J460 consumes the 0x5c-byte by-value Seeds once; this POD has no destructor.
    callbacks.start([=] { originalStart(object, type, challenge, seeds, difficulty); });
}
void __attribute__((fastcall)) consoleHook(void* object, void*, const void* text, bool silent,
                                           void* player) {
    const auto address = reinterpret_cast<std::uintptr_t>(text);
    const auto size = at<unsigned>(address, layout::string::size),
               capacity = at<unsigned>(address, layout::string::capacity);
    const auto data = capacity <= layout::string::inlineCapacity ? static_cast<const char*>(text)
                                                                 : at<const char*>(address);
    callbacks.consoleCommand({data, size}, [=] { originalConsole(object, text, silent, player); });
}
} // namespace
bool install(std::uintptr_t base, const Callbacks& handlers) {
    image = base;
    callbacks = handlers;
    auto hook = [](std::uintptr_t target, auto replacement, auto& original) {
        return MH_CreateHook(reinterpret_cast<void*>(target), reinterpret_cast<void*>(replacement),
                             reinterpret_cast<void**>(&original)) == MH_OK &&
               MH_EnableHook(reinterpret_cast<void*>(target)) == MH_OK;
    };
    return hook(image + j460::entry::managerSave, saveHook, originalSave) &&
           hook(image + j460::entry::managerDeleteSave, deleteHook, originalDelete) &&
           hook(image + j460::entry::managerSaveRerun, rerunHook, originalRerun) &&
           hook(image + j460::entry::managerExecuteMenu, menuHook, originalMenu) &&
           hook(image + j460::entry::progressSerialize, serializeHook, originalSerialize) &&
           hook(image + j460::entry::gameStart, startHook, originalStart) &&
           hook(image + j460::entry::managerExecuteStart, executeStartHook, originalExecuteStart) &&
           hook(image + j460::entry::gameUpdate, updateHook, originalUpdate) &&
           hook(image + j460::entry::consoleUpdate, consoleUpdateHook, originalConsoleUpdate) &&
           hook(image + j460::entry::consoleRunCommand, consoleHook, originalConsole) &&
           hook(image + j460::entry::gameControls, controlsHook, originalControls);
}
bool managerReady() {
    return image && manager();
}
bool gameReady() {
    return image && game();
}
bool continueAvailable() {
    return at<bool>(manager(), layout::manager::continueAvailable);
}
void continueAvailable(bool value) {
    at<bool>(manager(), layout::manager::continueAvailable) = value;
}
unsigned saveSlot() {
    return at<unsigned>(manager(), layout::manager::saveSlot);
}
void captureSave() {
    using Capture = void(__attribute__((thiscall))*)(void*, void*);
    reinterpret_cast<Capture>(image + j460::entry::runtimeNetCapture)(
        reinterpret_cast<void*>(game()),
        reinterpret_cast<void*>(manager() + layout::manager::saveState));
}
void suppressDelete() {
    at<bool>(manager(), layout::manager::deleteSaveRequested) = false;
}
void clearSave() {
    reinterpret_cast<Method>(image + j460::entry::runtimeNetClear)(
        reinterpret_cast<void*>(manager() + layout::manager::saveState));
}
lan::Progress readProgress() {
    lan::Progress value;
    const auto base = manager() + layout::manager::progress;
    std::memcpy(value.achievements.data(),
                reinterpret_cast<void*>(base + layout::progress::achievements),
                value.achievements.size());
    std::memcpy(value.counters.data(), reinterpret_cast<void*>(base + layout::progress::counters),
                sizeof(value.counters));
    return value;
}
void writeProgress(const lan::Progress& value) {
    const auto base = manager() + layout::manager::progress;
    std::memcpy(reinterpret_cast<void*>(base + layout::progress::achievements),
                value.achievements.data(), value.achievements.size());
    std::memcpy(reinterpret_cast<void*>(base + layout::progress::counters), value.counters.data(),
                sizeof(value.counters));
}
int pause() {
    return gameReady() ? at<int>(game(), layout::game::pauseMenu) : 0;
}
int scene() {
    return managerReady() ? at<int>(manager(), layout::manager::scene) : -1;
}
bool cinematicFinished() {
    return !at<bool>(manager(), layout::manager::cinematicActive) && scene() == j460::scene::game;
}
bool exitRequested() {
    return at<bool>(manager(), layout::manager::menuRequested) &&
           at<int>(manager(), layout::manager::requestedMenu) == j460::menuRequest::exitGame;
}
void cancelExit() {
    at<bool>(manager(), layout::manager::menuRequested) = false;
}
void resetPause() {
    reinterpret_cast<Method>(image + j460::entry::runtimeNetExecuteStart)(
        reinterpret_cast<void*>(game() + layout::game::pauseMenu));
}
void pollConsole() {
    if (gameReady() && originalConsoleUpdate)
        originalConsoleUpdate(reinterpret_cast<void*>(game() + layout::game::console));
}
void controls() {
    originalControls();
}
std::uint32_t parseSeed(std::string_view text) {
    constexpr unsigned seedGroupLength = 4;
    struct SmallString {
        char text[layout::string::inlineBytes]{};
        unsigned size = seedGroupLength * 2 + 1, capacity = layout::string::inlineCapacity;
    } value;
    if (text.size() != seedGroupLength * 2)
        return 0;
    std::memcpy(value.text, text.data(), seedGroupLength);
    value.text[seedGroupLength] = ' ';
    std::memcpy(value.text + seedGroupLength + 1, text.data() + seedGroupLength, seedGroupLength);
    using Parse = std::uint32_t(__cdecl*)(const SmallString*);
    return reinterpret_cast<Parse>(image + j460::entry::runtimeNetParseSeed)(&value);
}
void start(std::uint32_t seed, int character, unsigned difficulty) {
    Seeds seeds{};
    using Set = void(__attribute__((thiscall))*)(void*, std::uint32_t);
    reinterpret_cast<Method>(image + j460::entry::runtimeNetSeedConstructor)(&seeds);
    reinterpret_cast<Set>(image + j460::entry::runtimeNetSetSeed)(&seeds, seed);
    reinterpret_cast<Start>(image + j460::entry::runtimeNetStartGame)(
        reinterpret_cast<void*>(manager()), character, 0, seeds, difficulty);
}
void requestContinue() {
    at<bool>(manager(), layout::manager::continueRequested) = true;
}
lan::Stage stage() {
    lan::Stage value;
    value.level = at<int>(game(), layout::game::stage);
    value.type = at<int>(game(), layout::game::stageType);
    std::memcpy(value.seeds.data(), reinterpret_cast<void*>(game() + layout::game::floorSeeds),
                sizeof(value.seeds));
    std::memcpy(value.stateFlags.data(), reinterpret_cast<void*>(game() + layout::game::stateFlags),
                sizeof(value.stateFlags));
    return value;
}
void applyStage(const lan::Stage& value) {
    std::memcpy(reinterpret_cast<void*>(game() + layout::game::floorSeeds), value.seeds.data(),
                sizeof(value.seeds));
    std::memcpy(reinterpret_cast<void*>(game() + layout::game::stateFlags), value.stateFlags.data(),
                sizeof(value.stateFlags));
}
} // namespace isaac::engine::session

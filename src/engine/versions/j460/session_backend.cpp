#include "engine/session_backend.h"
#include "engine/versions/j460/entrypoints.h"
#include <MinHook.h>
#include <cstring>

namespace isaac::engine::session {
namespace {
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
    std::array<std::uint32_t, 23> words;
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
    if (reinterpret_cast<std::uintptr_t>(object) == manager() + 0x14)
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
    const auto size = at<unsigned>(address, 16), capacity = at<unsigned>(address, 20);
    const auto data = capacity < 16 ? static_cast<const char*>(text) : at<const char*>(address);
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
    return at<bool>(manager(), 0x20dcc);
}
void continueAvailable(bool value) {
    at<bool>(manager(), 0x20dcc) = value;
}
unsigned saveSlot() {
    return at<unsigned>(manager(), 0x10);
}
void captureSave() {
    using Capture = void(__attribute__((thiscall))*)(void*, void*);
    reinterpret_cast<Capture>(image + j460::entry::runtimeNetCapture)(
        reinterpret_cast<void*>(game()), reinterpret_cast<void*>(manager() + 0xfa4));
}
void suppressDelete() {
    at<bool>(manager(), 0x4b284) = false;
}
void clearSave() {
    reinterpret_cast<Method>(image + j460::entry::runtimeNetClear)(
        reinterpret_cast<void*>(manager() + 0xfa4));
}
lan::Progress readProgress() {
    lan::Progress value;
    const auto base = manager() + 0x14;
    std::memcpy(value.achievements.data(), reinterpret_cast<void*>(base + 0x38),
                value.achievements.size());
    std::memcpy(value.counters.data(), reinterpret_cast<void*>(base + 0x2bc),
                sizeof(value.counters));
    return value;
}
void writeProgress(const lan::Progress& value) {
    const auto base = manager() + 0x14;
    std::memcpy(reinterpret_cast<void*>(base + 0x38), value.achievements.data(),
                value.achievements.size());
    std::memcpy(reinterpret_cast<void*>(base + 0x2bc), value.counters.data(),
                sizeof(value.counters));
}
int pause() {
    return gameReady() ? at<int>(game(), 0x23a74) : 0;
}
int scene() {
    return managerReady() ? at<int>(manager(), 8) : -1;
}
bool cinematicFinished() {
    return !at<bool>(manager(), 0x21618) && scene() == 2;
}
bool exitRequested() {
    return at<bool>(manager(), 0x4b288) && at<int>(manager(), 0x4b28c) == 2;
}
void cancelExit() {
    at<bool>(manager(), 0x4b288) = false;
}
void resetPause() {
    reinterpret_cast<Method>(image + j460::entry::runtimeNetExecuteStart)(
        reinterpret_cast<void*>(game() + 0x23a74));
}
void pollConsole() {
    if (gameReady() && originalConsoleUpdate)
        originalConsoleUpdate(reinterpret_cast<void*>(game() + 0x68d78));
}
void controls() {
    originalControls();
}
std::uint32_t parseSeed(std::string_view text) {
    struct SmallString {
        char text[16]{};
        unsigned size = 9, capacity = 15;
    } value;
    if (text.size() != 8)
        return 0;
    std::memcpy(value.text, text.data(), 4);
    value.text[4] = ' ';
    std::memcpy(value.text + 5, text.data() + 4, 4);
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
    at<bool>(manager(), 0x4b131) = true;
}
lan::Stage stage() {
    lan::Stage value;
    value.level = at<int>(game());
    value.type = at<int>(game(), 4);
    std::memcpy(value.seeds.data(), reinterpret_cast<void*>(game() + 0x1bb84), sizeof(value.seeds));
    std::memcpy(value.stateFlags.data(), reinterpret_cast<void*>(game() + 0x26548),
                sizeof(value.stateFlags));
    return value;
}
void applyStage(const lan::Stage& value) {
    std::memcpy(reinterpret_cast<void*>(game() + 0x1bb84), value.seeds.data(), sizeof(value.seeds));
    std::memcpy(reinterpret_cast<void*>(game() + 0x26548), value.stateFlags.data(),
                sizeof(value.stateFlags));
}
} // namespace isaac::engine::session

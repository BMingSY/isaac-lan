#include "test_support.h"
#include "engine/session_backend.h"
#include "core/chat.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
#endif
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <MinHook.h>
#include <array>
#include <cstring>
#include <vector>

#ifdef ISAAC_LAN_TEST_J835
extern "C" {
void* completionTarget = nullptr;
void* completionGame = nullptr;
unsigned completionEvent = 0, completionCharacter = 0;
unsigned completionBefore = 0, completionAfter = 0, completionFlags = 0;
unsigned completionRegisters[8]{};
alignas(16) unsigned char completionInitialFloating[512]{}, completionFloating[512]{};
__attribute__((naked)) void completionOriginal() {
    __asm__ __volatile__("pushfl\n\tpushal\n\tmovl %esp, %esi\n\t"
                         "movl $_completionRegisters, %edi\n\tmovl $8, %ecx\n\tcld\n\trep movsl\n\t"
                         "movl 32(%esp), %eax\n\tmovl %eax, _completionFlags\n\t"
                         "fxsave _completionFloating\n\tpopal\n\tpopfl\n\tret");
}
__attribute__((naked)) void invokeCompletion() {
    __asm__ __volatile__(
        "pushfl\n\tpushal\n\tmovl %esp, _completionBefore\n\tmovl $0x12345678, %ebp\n\t"
        "movl _completionGame, %edi\n\tmovl _completionEvent, %esi\n\t"
        "movl _completionCharacter, %ebx\n\tmovl $0x87654321, %eax\n\t"
        "movl $0x22334455, %edx\n\tmovl $0x33445566, %ecx\n\t"
        "pcmpeqd %xmm7, %xmm7\n\tfld1\n\tfxsave _completionInitialFloating\n\t"
        "cmpl %eax, %eax\n\tstc\n\tcall *_completionTarget\n\t"
        "movl %esp, _completionAfter\n\tmovl _completionBefore, %esp\n\tfstp %st(0)\n\t"
        "popal\n\tpopfl\n\tret");
}
}
#endif
namespace {
namespace session = isaac::engine::session;
using Address = std::uintptr_t;
using Method = void(__attribute__((thiscall)) *)(void*);
using Plain = void(__cdecl*)();
constexpr unsigned imageSize = 0x900000;
// Independent fixture layouts: deliberately do not include the production layout/bindings.
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned stateOffset = 0xf34, continueFlag = 0x209c4, continueIntent = 0x1ea6c1;
constexpr unsigned deleteIntent = 0x1ea814, cinematicIntent = 0x1ea830;
constexpr unsigned menuIntent = 0x1ea818, menuTarget = 0x1ea81c;
constexpr unsigned pauseOffset = 0x10203c, consoleOffset = 0x1bb60, consoleState = 0x20;
constexpr unsigned floorSeeds = 0x1bb04, stateFlags = 0x1c3168;
constexpr unsigned fadeAction = 0x1c31b0, fadeAlpha = 0x1c31a8, heldFrames = 0x1c31b4;
constexpr unsigned achievementCount = 638, counterCount = 496, countersOffset = 0x2b8;
constexpr int restartAction = 4, heldAction = 5;
#else
constexpr unsigned stateOffset = 0xfcc, continueFlag = 0x20f1c, continueIntent = 0x4b409;
constexpr unsigned deleteIntent = 0x4b55c, cinematicIntent = 0x21768;
constexpr unsigned menuIntent = 0x4b560, menuTarget = 0x4b564;
constexpr unsigned pauseOffset = 0x23a7c, consoleOffset = 0x69468, consoleState = 0;
constexpr unsigned floorSeeds = 0x1bb84, stateFlags = 0x26558;
constexpr unsigned fadeAction = 0x265cc, fadeAlpha = 0x265c0, heldFrames = 0x265d4;
constexpr unsigned achievementCount = 642, counterCount = 523, countersOffset = 0x2bc;
constexpr int restartAction = 5, heldAction = 6;
#endif
constexpr unsigned progressOffset = 0x14;
std::vector<unsigned char> manager(0x220000), game(0x290000);
unsigned char* image;
bool forward = true, acceptRestart = true, requestedHeld;
unsigned restartRequests, nativeControls, parsedSeeds, allocations;
int controlAction;
std::vector<std::string> events;
std::vector<std::array<unsigned, 3>> awards;
std::string observerError;
bool throwAward = false;
std::string consolePayload = "result";
constexpr Address presentationActor = 0x12345678;
template <class T> T& field(void* base, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(base) + offset);
}
template <class Fn> Fn entry(unsigned rva) {
    return reinterpret_cast<Fn>(image + rva);
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    field<std::int32_t>(image, rva + 1) =
        reinterpret_cast<Address>(fn) - reinterpret_cast<Address>(image + rva + 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void checkReceiver(void* object, void* expected, const char* label) {
    require(object == expected, label);
}
void dispatch(const char* label, const session::Call& original) {
    events.emplace_back(label);
    if (forward)
        original();
}
void __cdecl save() {
    events.emplace_back("save");
}
#ifdef ISAAC_LAN_TEST_J835
void __attribute__((fastcall)) eraseSlot(void*, void*) {
    events.emplace_back("erase-slot-file");
}
#endif
void __cdecl erase() {
    events.emplace_back("delete");
}
void __cdecl rerun() {
    events.emplace_back("rerun");
}
void __cdecl unrelated() {
    events.emplace_back("unrelated");
}
void __cdecl replacement() {
    events.emplace_back("unrelated-hook");
}
#ifndef ISAAC_LAN_TEST_J835
unsigned nativeCompletions = 0;
void __stdcall completionOriginal(unsigned, unsigned, unsigned) {
    ++nativeCompletions;
}
#endif
void award(unsigned counter, unsigned bits, unsigned achievement) {
    awards.push_back({counter, bits, achievement});
#ifdef ISAAC_LAN_TEST_J835
    unsigned control;
    __asm__ __volatile__("stmxcsr %0" : "=m"(control));
    control ^= 0x6000;
    __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0" : : "m"(control) : "xmm7");
#endif
    if (throwAward)
        throw std::runtime_error("Fixture award failure");
}
void __cdecl controls() {
    ++nativeControls;
    field<int>(game.data(), fadeAction) = controlAction;
}
void __attribute__((fastcall)) serialize(void*, void*) {
    events.emplace_back("serialize");
}
void __attribute__((fastcall)) executeStart(void* object, void*) {
    checkReceiver(object, manager.data(), "ExecuteStart receiver");
    events.emplace_back("execute-start");
}
void __attribute__((fastcall)) executeMenu(void* object, void*) {
    checkReceiver(object, manager.data(), "ExecuteMenu receiver");
    events.emplace_back("menu");
}
void __attribute__((fastcall)) update(void* object, void*) {
    checkReceiver(object, game.data(), "Update receiver");
    events.emplace_back("update");
}
void __attribute__((fastcall)) consoleInput(void* object, void*) {
    checkReceiver(object, game.data() + consoleOffset, "Console input receiver");
    events.emplace_back("console-input");
}
void __attribute__((fastcall)) capture(void* object, void*, void* state) {
    checkReceiver(object, game.data(), "Capture receiver");
    checkReceiver(state, manager.data() + stateOffset, "Capture GameState");
    events.emplace_back("capture");
}
void __attribute__((fastcall)) clear(void* object, void*) {
    checkReceiver(object, manager.data() + stateOffset, "Clear receiver");
    events.emplace_back("clear");
}
void __attribute__((fastcall)) resetPause(void* object, void*) {
    checkReceiver(object, game.data() + pauseOffset, "Pause reset receiver");
    field<int>(object) = 0;
}
#ifdef ISAAC_LAN_TEST_J835
void __attribute__((fastcall)) persist(void* object, void*, bool backup) {
    checkReceiver(object, manager.data() + progressOffset, "Persist receiver");
    require(backup && field<bool>(object),
            "J835 must mark merged progress dirty and request backup");
    field<bool>(object) = false;
    events.emplace_back("flush");
}
#else
void __attribute__((fastcall)) persistCloud(void* object, void*) {
    checkReceiver(object, manager.data() + progressOffset, "Cloud progress receiver");
    events.emplace_back("cloud");
}
void __attribute__((fastcall)) persistFile(void* object, void*) {
    checkReceiver(object, manager.data() + progressOffset, "File progress receiver");
    events.emplace_back("file");
}
#endif
struct Seeds {
    std::array<std::uint32_t, 23> words;
};
static_assert(sizeof(Seeds) == 0x5c);
void validateStart(int type, int challenge, const Seeds& seeds, unsigned difficulty) {
    require(type == 19 && challenge == 0 && difficulty == 3, "Start stack arguments");
    require(seeds.words[1] == 0xabcdef01 && seeds.words.back() == 122, "By-value Seeds copy");
}
#ifdef ISAAC_LAN_TEST_J835
using Start = void(__stdcall*)(int, int, Seeds, unsigned);
void __stdcall gameStart(int type, int challenge, Seeds seeds, unsigned difficulty) {
#else
using Start = void(__attribute__((thiscall)) *)(void*, int, int, Seeds, unsigned);
void __attribute__((fastcall)) gameStart(void* object, void*, int type, int challenge, Seeds seeds,
                                         unsigned difficulty) {
    checkReceiver(object, game.data(), "Game::Start receiver");
#endif
    validateStart(type, challenge, seeds, difficulty);
    events.emplace_back("start");
}
#ifdef ISAAC_LAN_TEST_J835
void __stdcall startNew(int type, int challenge, Seeds seeds, unsigned difficulty) {
#else
void __attribute__((fastcall)) startNew(void* object, void*, int type, int challenge, Seeds seeds,
                                        unsigned difficulty) {
    checkReceiver(object, manager.data(), "Manager::StartNewGame receiver");
#endif
    validateStart(type, challenge, seeds, difficulty);
    events.emplace_back("start-new");
}
void __attribute__((fastcall)) constructSeeds(Seeds* seeds, void*) {
    for (unsigned i = 0; i < seeds->words.size(); ++i)
        seeds->words[i] = 100 + i;
}
void __attribute__((fastcall)) setSeed(Seeds* seeds, void*, std::uint32_t seed) {
    seeds->words[1] = seed;
}
// The fixtures implement the native ABI independently, including MSVC's inline string.
struct String {
    std::array<char, 16> storage{};
    unsigned size = 0, capacity = 15;
    const char* data() const {
        return capacity < 16 ? storage.data() : field<char*>(const_cast<String*>(this));
    }
};
static_assert(sizeof(String) == 24);
std::uint32_t __cdecl parseSeed(const String* text) {
    ++parsedSeeds;
    require(text->size == 9 && text->capacity == 15, "Seed string layout");
    require(std::string_view(text->data(), text->size) == "ABCD EFGH", "Seed grouping");
    return 0xabcdef01;
}
void* __attribute__((fastcall)) assign(String* text, void*, const char* data, unsigned size) {
    require(text->capacity == 15 && text->size == 0, "Native string must start empty");
    char* target = text->storage.data();
    if (size >= 16) {
        target = static_cast<char*>(HeapAlloc(GetProcessHeap(), 0, size + 1));
        require(target, "Fixture allocation");
        field<char*>(text) = target;
        text->capacity = size;
        ++allocations;
    }
    text->size = size;
    std::memcpy(target, data, size);
    target[size] = 0;
    return text;
}
void __attribute__((fastcall)) destroy(String* text, void*) {
    if (text->capacity >= 16) {
        require(HeapFree(GetProcessHeap(), 0, field<void*>(text)), "Native string allocator");
        --allocations;
    }
    *text = {};
}
using Print = void(__attribute__((thiscall)) *)(void*, const String*, unsigned, unsigned);
void __attribute__((fastcall)) print(void* object, void*, const String*, unsigned color,
                                     unsigned fade) {
    checkReceiver(object, game.data() + consoleOffset, "Console print receiver");
    require(color == 0xffabcd12 && fade == 37, "Console print stack arguments");
    events.emplace_back("print");
}
void emit(void* object, std::string_view value) {
    String text;
    assign(&text, nullptr, value.data(), value.size());
    entry<Print>(backend::entry::consolePrint)(object, &text, 0xffabcd12, 37);
    destroy(&text, nullptr);
}
using Command = void(__attribute__((thiscall)) *)(void*, const String*, bool, void*);
void __attribute__((fastcall)) command(void* object, void*, const String* text, bool silent,
                                       void* player) {
    checkReceiver(object, game.data() + consoleOffset, "Console command receiver");
    require(!silent && reinterpret_cast<Address>(player) == presentationActor,
            "Console command arguments");
    const std::string_view value(text->data(), text->size);
    if (value == "throw with allocated native storage")
        throw std::runtime_error("fixture");
    if (value == "outer") {
        emit(object, "before");
        require(session::executeConsole("inner") == "inside", "Nested command capture");
        emit(object, "after");
    } else {
        emit(object, value == "inner" ? "inside" : consolePayload);
    }
}
session::Callbacks handlers() {
    return {
        .save = [](const auto& call) { dispatch("save-hook", call); },
        .protectsSoloSave =
            [] {
                events.emplace_back("delete-hook");
                return !forward;
            },
        .saveRerun = [](const auto& call) { dispatch("rerun-hook", call); },
        .serializeProgress = [](const auto& call) { dispatch("serialize-hook", call); },
        .executeStart = [](const auto& call) { dispatch("execute-start-hook", call); },
        .start = [](const auto& call) { dispatch("start-hook", call); },
        .update = [](const auto& call) { dispatch("update-hook", call); },
        .consoleUpdate = [](const auto& call) { dispatch("console-input-hook", call); },
        .consoleCommand =
            [](std::string_view text, const auto& call) {
                require(text == "native command", "Borrowed command string");
                dispatch("command-hook", call);
            },
        .controls = [](const auto& call) { dispatch("controls-hook", call); },
        .executeMenu = [](const auto& call) { dispatch("menu-hook", call); },
        .restartRequest =
            [](bool held) {
                ++restartRequests;
                requestedHeld = held;
                return acceptRestart;
            },
        .completionAward = award,
        .largeFloor = nullptr,
        .deleteThis = nullptr,
    };
}
void prepare() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize synthetic image");
    patch(backend::entry::managerSave, save);
    patch(backend::entry::managerDeleteSave, erase);
#ifdef ISAAC_LAN_TEST_J835
    patch(backend::entry::gameStateDeleteFile, eraseSlot);
#endif
    patch(backend::entry::managerSaveRerun, rerun);
    patch(backend::entry::managerExecuteMenu, executeMenu);
    patch(backend::entry::progressSerialize, serialize);
    patch(backend::entry::gameStart, gameStart);
    patch(backend::entry::managerExecuteStart, executeStart);
    patch(backend::entry::gameUpdate, update);
    patch(backend::entry::consoleUpdate, consoleInput);
    patch(backend::entry::consoleRunCommand, command);
    patch(backend::entry::consolePrint, print);
    patch(backend::entry::gameControls, controls);
    patch(backend::entry::runtimeNetCapture, capture);
    patch(backend::entry::runtimeNetClear, clear);
    patch(backend::entry::runtimeNetExecuteStart, resetPause);
    patch(backend::entry::frontendAssign, assign);
    patch(backend::entry::frontendMenuUpdate, destroy);
    patch(backend::entry::runtimeNetParseSeed, parseSeed);
    patch(backend::entry::runtimeNetSeedConstructor, constructSeeds);
    patch(backend::entry::runtimeNetSetSeed, setSeed);
    patch(backend::entry::runtimeNetStartGame, startNew);
#ifdef ISAAC_LAN_TEST_J835
    patch(backend::entry::progressPersist, persist);
    patch(backend::entry::recordCompletionBoundary, completionOriginal);
#else
    patch(backend::entry::progressSaveCloud, persistCloud);
    patch(backend::entry::progressSaveFile, persistFile);
    patch(backend::entry::recordCharacterCompletion, completionOriginal);
#endif
    constexpr unsigned independent = 0x1000;
    patch(independent, unrelated);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    auto* collision = image + backend::entry::gameControls;
    require(MH_CreateHook(image + independent, reinterpret_cast<void*>(replacement), nullptr) ==
                    MH_OK &&
                MH_EnableHook(image + independent) == MH_OK &&
                MH_CreateHook(collision, reinterpret_cast<void*>(replacement), nullptr) == MH_OK,
            "Install independent hooks");
    require(!session::install(reinterpret_cast<Address>(image), handlers()),
            "Partial install must fail");
    require(!session::managerReady() && !session::gameReady(),
            "Failed install must clear readiness");
    entry<Plain>(independent)();
    require(events.back() == "unrelated-hook" && MH_RemoveHook(collision) == MH_OK,
            "Failure cleanup must preserve hooks owned by other components");
    require(session::install(reinterpret_cast<Address>(image), handlers()), "Retry after rollback");
    require(!session::managerReady() && !session::gameReady() && session::scene() == -1 &&
                session::pause() == 0,
            "Missing native objects");
    field<void*>(image, backend::globals::manager) = manager.data();
    field<void*>(image, backend::globals::game) = game.data();
    require(session::managerReady() && session::gameReady(), "Native globals");
    require(!session::install(reinterpret_cast<Address>(image), handlers()),
            "Duplicate installation");
}
void completion() {
    // The native descriptor table uses an 18-entry, two-word record per character.
    constexpr unsigned character = 5, stride = 18 * 8;
    const auto descriptor = backend::globals::completionDefinitions + character * stride;
    field<std::array<unsigned, 2>>(image, descriptor) = {32, 45};
    field<std::array<unsigned, 2>>(image, descriptor + 8) = {46, 67};
    const auto invoke = [&](unsigned event, unsigned owner, unsigned difficulty) {
#ifdef ISAAC_LAN_TEST_J835
        completionTarget = image + backend::entry::recordCompletionBoundary;
        completionGame = game.data();
        completionEvent = event;
        completionCharacter = owner;
        field<unsigned>(game.data(), 0x243624) = difficulty;
        invokeCompletion();
        require(completionBefore == completionAfter &&
                    completionRegisters[0] == reinterpret_cast<Address>(game.data()) &&
                    completionRegisters[1] == event && completionRegisters[2] == 0x12345678 &&
                    completionRegisters[4] == owner && completionRegisters[5] == 0x22334455 &&
                    completionRegisters[6] == 0x33445566 && completionRegisters[7] == 0x87654321 &&
                    (completionFlags & 0x41) == 0x41,
                "Completion branch damaged stack, registers or flags");
        require(std::memcmp(completionInitialFloating, completionFloating, 28) == 0 &&
                    std::memcmp(completionInitialFloating + 32, completionFloating + 32, 10) == 0 &&
                    std::memcmp(completionInitialFloating + 160, completionFloating + 160, 128) ==
                        0,
                "Completion branch damaged x87, MXCSR or SSE state");
#else
        const auto before = nativeCompletions;
        entry<void(__stdcall*)(unsigned, unsigned, unsigned)>(
            backend::entry::recordCharacterCompletion)(event, owner, difficulty);
        require(nativeCompletions == before + 1, "Completion observer suppressed native call");
#endif
    };
    for (unsigned difficulty : {0u, 1u, 2u, 3u}) {
        awards.clear();
        const bool hard = difficulty == 1 || difficulty == 3;
        invoke(0, character, difficulty);
        invoke(1, character, difficulty);
        invoke(1, character, difficulty); // Already-earned marks are still run earnings.
        const std::vector<std::array<unsigned, 3>> expected{{32, hard ? 3u : 1u, hard ? 45u : 0u},
                                                            {46, hard ? 3u : 1u, 67},
                                                            {46, hard ? 3u : 1u, 67}};
        require(awards == expected, "Completion event mapping, difficulty or repeated award");
    }
    awards.clear();
    invoke(15, character, 1);
    invoke(1, 41, 1);
    invoke(1, character, 4);
    {
        session::ProgressReadOnlyScope scope;
        invoke(1, character, 1);
    }
    require(awards.empty(), "Out-of-range or borrowed progress earned a completion");
    throwAward = true;
    invoke(1, character, 1);
    require(observerError == "Fixture award failure", "Observer failure crossed native frame");
    throwAward = false;
    invoke(1, character, 1);
    require(awards.size() == 2, "Observer did not recover after callback failure");
}
void hooks() {
    events.clear();
    for (bool pass : {true, false}) {
        forward = pass;
        events.clear();
        entry<Plain>(backend::entry::managerSave)();
        entry<Plain>(backend::entry::managerDeleteSave)();
        entry<Plain>(backend::entry::managerSaveRerun)();
        entry<Method>(backend::entry::managerExecuteMenu)(manager.data());
        entry<Method>(backend::entry::managerExecuteStart)(manager.data());
        entry<Method>(backend::entry::gameUpdate)(game.data());
        entry<Method>(backend::entry::consoleUpdate)(game.data() + consoleOffset);
        entry<Method>(backend::entry::progressSerialize)(manager.data() + progressOffset);
        const std::vector<std::string> labels{"save",          "delete",        "rerun",
                                              "menu",          "execute-start", "update",
                                              "console-input", "serialize"};
        std::vector<std::string> expected;
        for (const auto& label : labels) {
            expected.push_back(label + "-hook");
            if (pass)
                expected.push_back(label);
        }
        require(events == expected, "Hook forwarding and suppression order");
    }
#ifdef ISAAC_LAN_TEST_J835
    for (const bool protectedSlot : {true, false}) {
        forward = !protectedSlot;
        events.clear();
        const auto eraseFile = entry<Method>(backend::entry::gameStateDeleteFile);
        eraseFile(manager.data() + stateOffset);
        eraseFile(game.data());
        require(
            events == std::vector<std::string>{"delete-hook",
                                               protectedSlot ? "clear" : "erase-slot-file",
                                               "erase-slot-file"},
            "Original exit must preserve the protected solo file and pass through unrelated slots");
    }
#endif
    forward = true;
    events.clear();
    entry<Method>(backend::entry::progressSerialize)(manager.data() + progressOffset + 0x1000);
    require(events == std::vector<std::string>{"serialize"},
            "Do not intercept unrelated progress objects");
    Seeds seeds;
    constructSeeds(&seeds, nullptr);
    setSeed(&seeds, nullptr, 0xabcdef01);
#ifdef ISAAC_LAN_TEST_J835
    entry<Start>(backend::entry::gameStart)(19, 0, seeds, 3);
#else
    entry<Start>(backend::entry::gameStart)(game.data(), 19, 0, seeds, 3);
#endif
    require(events[1] == "start-hook" && events[2] == "start", "Game start callback");
    session::start(0xabcdef01, 19, 3);
    require(events.back() == "start-new", "StartNewGame path");
    require(session::parseSeed("short") == 0 && parsedSeeds == 0,
            "Reject invalid seed length before native call");
    require(session::parseSeed("ABCDEFGH") == 0xabcdef01 && parsedSeeds == 1, "Seed parser ABI");
}
void state() {
    session::continueAvailable(true);
    require(field<bool>(manager.data(), continueFlag) && session::continueAvailable(),
            "Continue availability");
    session::continueAvailable(false);
    require(!session::continueAvailable(), "Restore solo availability");
    session::requestContinue();
    require(field<bool>(manager.data(), continueIntent), "Continue request");
    field<unsigned>(manager.data(), 0x10) = 3;
    require(session::saveSlot() == 3, "Save slot");
    field<bool>(manager.data(), deleteIntent) = true;
    manager[deleteIntent + 1] = 0x5a;
    session::suppressDelete();
    require(!manager[deleteIntent] && manager[deleteIntent + 1] == 0x5a,
            "Suppress delete without adjacent state writes");
    field<int>(manager.data(), 8) = 2;
    field<bool>(manager.data(), cinematicIntent) = false;
    require(session::cinematicFinished(), "Game scene without pending cinematic");
    field<bool>(manager.data(), cinematicIntent) = true;
    require(!session::cinematicFinished(), "Pending cinematic");
    field<bool>(manager.data(), cinematicIntent) = false;
    field<int>(manager.data(), 8) = 3;
    require(!session::cinematicFinished(), "Playing cinematic");
    field<bool>(manager.data(), menuIntent) = true;
    field<int>(manager.data(), menuTarget) = 3;
    require(!session::exitRequested(), "Other menu request");
    field<int>(manager.data(), menuTarget) = 2;
    require(session::exitRequested(), "Exit intent");
    session::cancelExit();
    require(!session::exitRequested() && field<int>(manager.data(), menuTarget) == 2,
            "Cancel only pending intent");
    field<int>(game.data(), pauseOffset) = 3;
    require(session::pause() == 3, "Pause state");
    session::resetPause();
    require(session::pause() == 0, "Native pause reset");
    events.clear();
    session::captureSave();
    session::clearSave();
    require(events == std::vector<std::string>{"capture", "clear"}, "Save lifecycle");
    isaac::lan::Progress progress;
    progress.achievements.fill(1);
    progress.counters.fill(42);
    session::writeProgress(progress);
    const auto copied = session::readProgress();
    require(copied.achievements[achievementCount - 1] == 1 &&
                copied.counters[counterCount - 1] == 42,
            "Progress uses selected receiver and array limits");
    require(field<int>(manager.data(), progressOffset + countersOffset) == 42,
            "Counter native layout");
    for (unsigned i = counterCount; i < copied.counters.size(); ++i)
        require(copied.counters[i] == 0, "Unsupported progress must be zero");
    {
        session::ProgressReadOnlyScope outer;
        require(manager[progressOffset + 1] == 1, "Protect native progress");
        { session::ProgressReadOnlyScope inner; }
        require(manager[progressOffset + 1] == 1, "Nested scope restores previous protection");
    }
    require(manager[progressOffset + 1] == 0, "Restore writable progress");
    events.clear();
    session::persistProgress();
#ifdef ISAAC_LAN_TEST_J835
    require(events == std::vector<std::string>{"flush"}, "Original persistence selection");
#else
    require(events == std::vector<std::string>{"cloud", "file"}, "Plus persistence order");
#endif
    field<int>(game.data()) = 7;
    field<int>(game.data(), 4) = 2;
    constexpr unsigned seedScalarBytes = 0x54;
    constexpr std::array<std::uint32_t, 4> nativeOwners{0x13572468, 7, 0x24681357, 9};
    // Native Seeds ends in an owning map, followed by another Game member.
    // Neither pointer, count nor adjacent object may cross the stage wire.
    std::memcpy(game.data() + floorSeeds + seedScalarBytes, nativeOwners.data(),
                sizeof(nativeOwners));
    for (unsigned i = 0; i < seedScalarBytes / sizeof(std::uint32_t); ++i)
        field<std::uint32_t>(game.data(), floorSeeds + i * sizeof(std::uint32_t)) = 123 + i;
    field<std::uint32_t>(game.data(), stateFlags) = 456;
    auto stage = session::stage();
    require(stage.level == 7 && stage.type == 2 && stage.seeds.front() == 123 &&
                stage.seeds.back() == 143 && stage.stateFlags[0] == 456,
            "Stage capture");
    stage.level = 1;
    stage.seeds.fill(987);
    stage.stateFlags = {0x12345678, 0xabcdef01};
    session::applyStage(stage);
    const auto applied = session::stage();
    require(applied.level == 7 && applied.seeds == stage.seeds &&
                applied.stateFlags == stage.stateFlags,
            "Apply seeds and route flags without forcing the native transition");
    require(std::memcmp(game.data() + floorSeeds + seedScalarBytes, nativeOwners.data(),
                        sizeof(nativeOwners)) == 0,
            "Stage synchronization overwrote native map ownership or an adjacent object");
}
void restart() {
    for (bool accepted : {false, true}) {
        acceptRestart = accepted;
        for (int action = 0; action < 8; ++action) {
            controlAction = action;
            restartRequests = 0;
            field<float>(game.data(), fadeAlpha) = 0.75f;
            field<unsigned char>(game.data(), heldFrames) = 21;
            entry<Plain>(backend::entry::gameControls)();
            const bool requested = action == restartAction || action == heldAction;
            require(restartRequests == unsigned(requested),
                    "Only restart actions may be redirected");
            if (requested)
                require(requestedHeld == (action == heldAction), "Version-specific held restart");
            const bool consumed = requested && accepted;
            require(field<int>(game.data(), fadeAction) == (consumed ? 0 : action) &&
                        field<float>(game.data(), fadeAlpha) == (consumed ? 0 : 0.75f) &&
                        field<unsigned char>(game.data(), heldFrames) == (consumed ? 0 : 21),
                    "Consume accepted restart atomically, preserve other transitions");
        }
    }
    controlAction = heldAction;
    events.clear();
    const auto previous = nativeControls;
    session::controls();
    require(nativeControls == previous + 1 && events.empty() &&
                field<int>(game.data(), fadeAction) == 0,
            "Explicit controls call bypasses callback but redirects restart");
}
void console() {
    events.clear();
    session::pollConsole();
    require(events == std::vector<std::string>{"console-input"}, "Polling bypasses callback");
    field<int>(game.data(), consoleOffset + consoleState) = 2;
    session::hideConsole();
    require(field<int>(game.data(), consoleOffset + consoleState) == 0, "Console state offset");
    String text;
    assign(&text, nullptr, "native command", 14);
    forward = false;
    events.clear();
    entry<Command>(backend::entry::consoleRunCommand)(game.data() + consoleOffset, &text, false,
                                                      reinterpret_cast<void*>(presentationActor));
    require(events == std::vector<std::string>{"command-hook"}, "Intercept native command");
    forward = true;
    destroy(&text, nullptr);
    require(session::executeConsole("long enough to use the native heap") == "result" &&
                allocations == 0,
            "Owned command string and output capture");
    require(session::executeConsole("outer") == "beforeafter" && allocations == 0,
            "Restore nested capture");
    try {
        session::executeConsole("throw with allocated native storage");
        require(false, "Expected fixture exception");
    } catch (const std::runtime_error&) {
    }
    require(allocations == 0 && session::executeConsole("after exception") == "result",
            "Release native storage and restore capture on unwind");
    consolePayload.assign(isaac::chat::maxOutputBytes + 100, 'x');
    require(session::executeConsole("bounded").size() == isaac::chat::maxOutputBytes &&
                allocations == 0,
            "Bound captured console output");
}
} // namespace
namespace isaac::rooms {
std::uintptr_t presentationPlayer(void*) {
    return presentationActor;
}
} // namespace isaac::rooms
int main() {
    prepare();
    completion();
    hooks();
    state();
    restart();
    console();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release synthetic fixture");
}

namespace isaac::engine {
bool installGeneratedChallenge(std::uintptr_t, bool (*)()) {
    return true;
}
bool installFloorGeneration(std::uintptr_t, bool (*)()) {
    return true;
}
} // namespace isaac::engine

namespace isaac::runtime {
void abort(const std::string& error) {
    observerError = error;
}
} // namespace isaac::runtime

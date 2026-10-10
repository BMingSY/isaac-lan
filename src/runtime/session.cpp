#include "runtime/session.h"
#include "engine/item_presentation.h"
#include "engine/presentation.h"
#include "presentation/frontend.h"
#include "net/session.h"
#include "engine/rooms.h"
#include "engine/rewind.h"
#include "engine/input.h"
#include "core/lanbot_console.h"
#include "core/menu_input.h"
#include "engine/save.h"
#include "runtime/session_archive.h"
#include "runtime/progression.h"
#include <MinHook.h>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <chrono>

#include "engine/versions/j460/entrypoints.h"
namespace j460 = isaac::engine::j460;

namespace isaac::runtime {
namespace {
constexpr int registry = -1001000;
using LuaFunction = int(__cdecl*)(lua_State*);
struct API {
    void(__cdecl* pushClosure)(lua_State*, LuaFunction, int);
    void(__cdecl* setField)(lua_State*, int, const char*);
    void(__cdecl* createTable)(lua_State*, int, int);
    void(__cdecl* pushInteger)(lua_State*, long long);
    void(__cdecl* pushBoolean)(lua_State*, int);
    const char*(__cdecl* pushString)(lua_State*, const char*);
    const char*(__cdecl* pushLString)(lua_State*, const char*, std::size_t);
    long long(__cdecl* checkInteger)(lua_State*, int);
    const char*(__cdecl* checkString)(lua_State*, int, std::size_t*);
    const char*(__cdecl* toString)(lua_State*, int, std::size_t*);
    int(__cdecl* getTop)(lua_State*);
    int(__cdecl* getGlobal)(lua_State*, const char*);
    void(__cdecl* setTop)(lua_State*, int);
    void(__cdecl* pushValue)(lua_State*, int);
    int(__cdecl* type)(lua_State*, int);
    int(__cdecl* boolean)(lua_State*, int);
    int(__cdecl* ref)(lua_State*, int);
    void(__cdecl* unref)(lua_State*, int, int);
    int(__cdecl* rawGetI)(lua_State*, int, long long);
    int(__cdecl* pcall)(lua_State*, int, int, int, std::intptr_t, void*);
} lua{};
std::unique_ptr<lan::Session> session;
std::vector<std::unique_ptr<lan::Session>> retiring;
std::uintptr_t executableImage = 0;
void (*logger)(const std::string&) = nullptr;
bool launchRequested = false;
bool resumeLaunch = false;
bool authorizedExit = false;
std::string sessionFingerprint;
std::optional<lan::Archive> exitingArchive, resumingArchive;
bool exitingHost = false;
bool networkRun = false, soloContinueAvailable = false;
std::vector<std::uint8_t> soloState;
bool beginNetworkRun() {
    if (networkRun)
        return true;
    const auto manager =
        *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
    soloContinueAvailable = *reinterpret_cast<bool*>(manager + 0x20dcc);
    soloState = soloContinueAvailable ? save::encode(executableImage) : std::vector<std::uint8_t>{};
    if (soloContinueAvailable && soloState.empty()) {
        if (logger)
            logger("solo_backup=FAILED");
        return false;
    }
    networkRun = true;
    rooms::setConnected(15);
    return true;
}
using SaveGame = void(__cdecl*)();
SaveGame originalSaveGame, originalDeleteGame, originalSaveRerun;
void __cdecl saveGame() {
    if (!networkRun) {
        originalSaveGame();
        return;
    }
    // Native save normally opens/truncates the user's solo run before calling
    // its serializer. Keep the network state in memory and commit our separate
    // session archive after the engine's exit transaction instead.
    if (exitingArchive) {
        const auto manager =
            *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
        const auto game = *reinterpret_cast<void**>(executableImage + j460::globals::game);
        using Capture = void(__attribute__((thiscall))*)(void*, void*);
        reinterpret_cast<Capture>(executableImage + j460::entry::runtimeNetCapture)(
            game, reinterpret_cast<void*>(manager + 0xfa4));
    }
}
void __cdecl deleteGame() {
    if (!networkRun) {
        originalDeleteGame();
        return;
    }
    const auto manager =
        *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
    *reinterpret_cast<bool*>(manager + 0x4b284) = false;
}
void __cdecl saveRerun() {
    if (!networkRun)
        originalSaveRerun();
}
std::filesystem::path archivePath() {
    wchar_t executable[32768]{};
    GetModuleFileNameW(nullptr, executable, std::size(executable));
    const auto manager =
        *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
    const auto slot = *reinterpret_cast<unsigned*>(manager + 0x10);
    return std::filesystem::path(executable).parent_path() / L"isaac-lan" /
           (L"session-" + std::to_wstring(slot) + L".bin");
}
void writeArchive(const lan::Archive& archive) {
    const auto path = archivePath();
    const auto temporary = path.wstring() + L".tmp";
    const auto bytes = archive.encode();
    std::filesystem::create_directories(path.parent_path());
    std::ofstream file(temporary.c_str(), std::ios::binary | std::ios::trunc);
    file.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    file.close();
    if (!file || !MoveFileExW(temporary.c_str(), path.c_str(),
                              MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        throw std::runtime_error("Cannot commit LAN saved session");
    if (logger)
        logger("session_save=COMPLETE bytes=" + std::to_string(bytes.size()));
}
std::optional<lan::Archive> readArchive() {
    try {
        const auto path = archivePath();
        if (!std::filesystem::exists(path) ||
            std::filesystem::file_size(path) > lan::maxSnapshotSize)
            return {};
        std::ifstream file(path, std::ios::binary);
        const std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(file), {}};
        return lan::Archive::decode(bytes);
    } catch (const std::exception& error) {
        if (logger)
            logger("session_read=FAILED " + std::string(error.what()));
        return {};
    }
}
std::optional<lan::Progress> localProgress, commonProgress;
std::uintptr_t progressionAddress() {
    return *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager) + 0x14;
}
lan::Progress readProgress() {
    lan::Progress value;
    const auto base = progressionAddress();
    std::memcpy(value.achievements.data(), reinterpret_cast<void*>(base + 0x38),
                value.achievements.size());
    std::memcpy(value.counters.data(), reinterpret_cast<void*>(base + 0x2bc),
                value.counters.size() * 4);
    return value;
}
void writeProgress(const lan::Progress& value) {
    const auto base = progressionAddress();
    std::memcpy(reinterpret_cast<void*>(base + 0x38), value.achievements.data(),
                value.achievements.size());
    std::memcpy(reinterpret_cast<void*>(base + 0x2bc), value.counters.data(),
                value.counters.size() * 4);
}
void restoreProgress() {
    if (!localProgress || !commonProgress)
        return;
    const auto current = readProgress();
    // Keep each user's previous progress. Only changes earned during this
    // shared run are merged back; the host's old achievements are not granted.
    writeProgress(lan::mergeProgress(*localProgress, *commonProgress, current));
    localProgress.reset();
    commonProgress.reset();
}
using SerializeProgress = void(__attribute__((thiscall)) *)(void*);
SerializeProgress originalSerializeProgress;
void __attribute__((fastcall)) serializeProgress(void* p, void*) {
    if (!localProgress || !commonProgress ||
        reinterpret_cast<std::uintptr_t>(p) != progressionAddress()) {
        originalSerializeProgress(p);
        return;
    }
    const auto current = readProgress();
    writeProgress(lan::mergeProgress(*localProgress, *commonProgress, current));
    originalSerializeProgress(p);
    writeProgress(current);
    if (logger)
        logger("progress_save=ISOLATED");
}
lua_State* state = nullptr;
int captureRef = -2, applyRef = -2, captureStateRef = -2, restoreStateRef = -2, presentRef = -2,
    stageRef = -2;
lan::InputFrame localInput;
std::optional<lan::InputRoom> lastInputRoom;
std::optional<lan::WorldState> authoritative;
bool gated = false, pendingHalf = false;
bool playingEnding = false;
bool playingCinematic = false, cinematicReady = false;
std::uint32_t nextInputTick = 0;
using InputClock = std::chrono::steady_clock;
InputClock::time_point nextCaptureAt{};
std::optional<InputClock::time_point> rejoinAt;
constexpr auto inputPeriod = std::chrono::nanoseconds(1'000'000'000 / 30);
std::uint32_t nextTick = 0, currentTick = 0;
std::uint32_t floorEpoch = 0;
std::optional<lan::WorldState> replicaPending;
std::array<std::uint32_t, lan::maxPlayers> consumedInputSequences{};
struct StateCost {
    unsigned samples = 0;
    double total = 0, maximum = 0;
    void sample(InputClock::time_point start, const char* operation) {
        const double ms =
            std::chrono::duration<double, std::milli>(InputClock::now() - start).count();
        ++samples;
        total += ms;
        maximum = std::max(maximum, ms);
        if (samples == 300) {
            if (logger)
                logger(std::string("state_cost operation=") + operation + " mean_ms=" +
                       std::to_string(total / samples) + " max_ms=" + std::to_string(maximum));
            samples = 0;
            total = maximum = 0;
        }
    }
} captureCost, applyCost;
void (*runHalf)() = nullptr;
void (*restorePositions)() = nullptr;
using GameUpdate = void(__attribute__((thiscall)) *)(void*);
GameUpdate originalUpdate = nullptr;
using Controls = void(__cdecl*)();
Controls originalControls;
using ConsoleUpdate = void(__attribute__((thiscall)) *)(void*);
ConsoleUpdate originalConsoleUpdate = nullptr;
using ConsoleCommand = void(__attribute__((thiscall)) *)(void*, const void*, bool, void*);
ConsoleCommand originalConsoleCommand = nullptr;
void __attribute__((fastcall)) consoleCommand(void* console, void*, const void* text, bool silent,
                                              void* player) {
    // J460 uses the MSVC x86 string layout at this native boundary.
    const auto address = reinterpret_cast<std::uintptr_t>(text);
    const auto size = *reinterpret_cast<const unsigned*>(address + 16);
    const auto capacity = *reinterpret_cast<const unsigned*>(address + 20);
    const auto data =
        capacity < 16 ? static_cast<const char*>(text) : *static_cast<const char* const*>(text);
    const auto command = std::string_view(data, size);
    if (const auto args = input::consoleArguments(command, "rewind");
        args && gated && session && session->phase() == lan::Phase::running) {
        // Native console rewind restores its process-wide room buffer. LAN
        // suppresses that buffer in favor of controller checkpoints, so the
        // native command would end the session and restart with an empty seed.
        const bool queued = session->isHost() && rooms::stateReady() &&
                            args->find_first_not_of(" \t\r\n") == std::string_view::npos &&
                            rewind::request(0);
        if (logger)
            logger(queued ? "console_rewind=QUEUED" : "console_rewind=IGNORED unavailable");
        return;
    }
    const auto args = input::botConsoleArguments(command);
    if (args && state) {
        const int top = lua.getTop(state);
        if (lua.getGlobal(state, "_IsaacLanBotCommand") == 6) {
            lua.pushLString(state, args->data(), args->size());
            if (lua.pcall(state, 1, 0, 0, 0, nullptr) && logger) {
                const auto reason = lua.toString(state, -1, nullptr);
                logger(std::string("lanbot_console_error=") + (reason ? reason : "Lua error"));
            }
            lua.setTop(state, top);
            return;
        }
        lua.setTop(state, top);
    }
    originalConsoleCommand(console, text, silent, player);
}
void __attribute__((fastcall)) consoleUpdate(void* console, void*) {
    // LAN services this local interface once per render, independently of the
    // host's 30 Hz simulation and the guest's snapshot presentation.
    if (!gated || !session || session->phase() != lan::Phase::running)
        originalConsoleUpdate(console);
}
void __cdecl controls() {
    if (!gated || playingEnding || playingCinematic)
        originalControls();
}
struct SeedValue {
    std::array<std::uint32_t, 23> words;
};
static_assert(sizeof(SeedValue) == 0x5c);
using StartGame = void(__attribute__((thiscall)) *)(void*, int, int, SeedValue, unsigned);
StartGame originalStart = nullptr;
using ExecuteStart = void(__attribute__((thiscall)) *)(void*);
ExecuteStart originalExecuteStart;
void fail(const std::string& error);
lan::Archive captureCheckpoint();
void __attribute__((fastcall)) executeStart(void* manager, void*) {
    const bool resume = resumeLaunch && session && session->phase() == lan::Phase::running;
    if (resume) {
        rooms::beforeStart();
        input::reset();
        // Hotplug IDs can change after returning to the menu. Native Continue
        // drops players whose saved controller is absent, before Lua can bind
        // them. Restore LAN device IDs before that roster is reconstructed.
        input::prepareControllers();
        if (session->settings().progress && !localProgress) {
            localProgress = readProgress();
            commonProgress = session->settings().progress;
            writeProgress(*commonProgress);
        }
    }
    originalExecuteStart(manager);
    if (resume) {
        // Continue restores players before our controller assignment callback.
        // Clear the native reconnect/pause screen once every controller is
        // bound, just as the new-run path initializes PauseScreen.
        const auto game = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
        reinterpret_cast<ExecuteStart>(executableImage + j460::entry::runtimeNetExecuteStart)(
            reinterpret_cast<void*>(game + 0x23a74));
        resumeLaunch = false;
    }
}
void __attribute__((fastcall)) startGame(void* game, void*, int type, int challenge,
                                         SeedValue seeds, unsigned difficulty) {
    rooms::beforeStart();
    input::reset();
    const bool networkStart = session && session->phase() == lan::Phase::running;
    if (networkStart && !beginNetworkRun()) {
        session->abort("Cannot preserve the existing solo save");
        return;
    }
    if (networkStart && session->settings().progress && !localProgress) {
        localProgress = readProgress();
        commonProgress = session->settings().progress;
        writeProgress(*commonProgress);
    }
    // J460 consumes the by-value native Seeds argument (0x5c bytes). This POD
    // forwarding copy has no destructor; ownership is consumed exactly once by
    // the original function. Its verified stack cleanup is 0x68 bytes.
    originalStart(game, type, challenge, seeds, difficulty);
}

void fail(const std::string& error) {
    if (logger)
        logger("network_failure=" + error);
    if (session)
        session->abort(error);
}
bool call(int reference, int arguments, int results, int stackBefore) {
    (void)reference;
    if (lua.pcall(state, arguments, results, 0, 0, nullptr) == 0)
        return true;
    const char* error = lua.toString(state, -1, nullptr);
    fail(std::string("Game bridge callback failed: ") + (error ? error : "non-string Lua error"));
    lua.setTop(state, stackBefore);
    return false;
}
void integrationCallback(const char* name) {
    if (!state || !gated || !session)
        return;
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, name) == 6 && lua.pcall(state, 0, 0, 0, 0, nullptr) && logger) {
        const auto reason = lua.toString(state, -1, nullptr);
        logger(std::string("integration_error=") + name + " " + (reason ? reason : "Lua error"));
    }
    lua.setTop(state, top);
}
void publishState() {
    if (!session || !session->isHost() || session->phase() != lan::Phase::running)
        return;
    const auto game = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
    // Readiness can arrive between a game update and its half update. Publish
    // only the roster already applied to this game state; a new guest gets its
    // first view after setConnected has restored the actor and room.
    const auto simulatedMask = rooms::connected();
    for (unsigned slot = 1; slot < session->players(); ++slot) {
        if (!(simulatedMask & session->connectedMask() & (1u << slot)))
            continue;
        const int top = lua.getTop(state);
        const auto began = InputClock::now();
        lua.rawGetI(state, registry, captureStateRef);
        lua.pushInteger(state, slot);
        lua.pushInteger(state, currentTick);
        if (!call(captureStateRef, 2, 1, top))
            return;
        captureCost.sample(began, "capture");
        std::size_t size = 0;
        const auto bytes = lua.toString(state, -1, &size);
        if (!bytes || !size || size > lan::maxWorldSize) {
            lua.setTop(state, top);
            fail("Invalid authoritative world state");
            return;
        }
        lan::WorldState packet;
        packet.tick = currentTick;
        packet.connected = simulatedMask;
        packet.paused = *reinterpret_cast<int*>(game + 0x23a74) != 0;
        packet.pauseOwner = input::menuOwner();
        packet.inputSequences = consumedInputSequences;
        packet.bytes.assign(bytes, bytes + size);
        session->publish(slot, packet);
        lua.setTop(state, top);
    }
    session->poll();
}
bool captureNextInput() {
    if (!gated || !session || playingEnding || playingCinematic ||
        session->phase() != lan::Phase::running)
        return false;
    const auto now = InputClock::now();
    if (now < nextCaptureAt)
        return true;
    const int top = lua.getTop(state);
    lua.rawGetI(state, registry, captureRef);
    if (!call(captureRef, 0, 1, top))
        return false;
    std::size_t size = 0;
    const auto data = lua.toString(state, -1, &size);
    if (!data || size != lan::actionCount * 2 + 2) {
        lua.setTop(state, top);
        fail("Invalid local controls");
        return false;
    }
    lan::Reader reader{std::span(reinterpret_cast<const std::uint8_t*>(data), size)};
    localInput = reader.input();
    lua.setTop(state, top);
    std::optional<lan::InputRoom> inputRoom;
    const auto locations = rooms::captureLocations();
    if (rooms::stateReady() && session->slot() < locations.size()) {
        const auto& position = locations[session->slot()];
        inputRoom = lan::InputRoom{floorEpoch, static_cast<std::int16_t>(position.index),
                                   static_cast<std::uint8_t>(position.dimension)};
        inputRoom->introSerial = presentation::playedIntro();
        inputRoom->introActive = presentation::introActive();
    }
    input::captureRoomInput(localInput, inputRoom, lastInputRoom, floorEpoch);
    if (!session->submit(nextInputTick, localInput, inputRoom)) {
        fail("Local input sequence rejected");
        return false;
    }
    ++nextInputTick;
    nextCaptureAt =
        now - nextCaptureAt >= inputPeriod ? now + inputPeriod : nextCaptureAt + inputPeriod;
    return true;
}
void updateReplica(void* game) {
    const auto g = reinterpret_cast<std::uintptr_t>(game);
    // A faster host can finish another floor while this replica is still
    // initializing the previous one. Leave the reliable event in the session
    // until the native roster is ready; keep updating the loading floor below.
    if (auto transition = rooms::stateReady() ? session->takeStage() : std::nullopt) {
        replicaPending.reset();
        authoritative.reset();
        // A returning client may still have its actor parked according to the
        // checkpoint roster. The readiness event admits this local controller
        // before a deferred native floor event can name its player object.
        rooms::setConnected(session->connectedMask() | (1u << session->slot()));
        floorEpoch = transition->epoch;
        // Native Forget Me Now, five-pip rooms and R Key update Seeds before
        // starting the transition. A stage number alone regenerates the old
        // client topology, whose missing descriptor can crash the minimap.
        if (transition->rewind.empty()) {
            std::memcpy(reinterpret_cast<void*>(g + 0x1bb84), transition->seeds.data(),
                        sizeof(transition->seeds));
            // Route flags are set by authoritative trapdoor gameplay. Replicas
            // must inherit them before native next-floor selection, not after
            // loading a normal floor and discovering mismatched descriptors.
            std::memcpy(reinterpret_cast<void*>(g + 0x26548), transition->stateFlags.data(),
                        sizeof(transition->stateFlags));
        }
        const int top = lua.getTop(state);
        lua.rawGetI(state, registry, stageRef);
        lua.pushInteger(state, transition->epoch);
        lua.pushInteger(state, transition->level);
        lua.pushInteger(state, transition->type);
        lua.pushInteger(state, transition->animation);
        lua.pushBoolean(state, transition->same);
        lua.pushLString(state, reinterpret_cast<const char*>(transition->rewind.data()),
                        transition->rewind.size());
        lua.pushBoolean(state, transition->rKey);
        lua.pushInteger(state, transition->cinematic);
        playingCinematic = transition->cinematic != 0;
        cinematicReady = false;
        if (playingCinematic) {
            input::reset();
            pendingHalf = false;
        }
        if (!call(stageRef, 8, 0, top))
            return;
        rooms::finishFrame();
        if (logger)
            logger("floor_event=RECEIVED epoch=" + std::to_string(floorEpoch));
    }
    if (playingCinematic)
        return;
    bool committedView = false;
    if (auto packet = session->takeState())
        replicaPending = std::move(packet);
    if (replicaPending) {
        auto& packet = replicaPending;
        currentTick = packet->tick;
        nextTick = currentTick + 1;
        const int top = lua.getTop(state);
        lua.rawGetI(state, registry, restoreStateRef);
        const auto began = InputClock::now();
        lua.pushLString(state, reinterpret_cast<const char*>(packet->bytes.data()),
                        packet->bytes.size());
        lua.pushInteger(state, packet->tick);
        lua.pushInteger(state, packet->inputSequences[session->slot()]);
        if (!call(restoreStateRef, 3, 1, top))
            return;
        applyCost.sample(began, "apply");
        // A valid new-floor snapshot can arrive while the native transition is
        // still running. Keep the newest view and retry after initialization.
        const bool applied = lua.type(state, -1) != 1 || lua.boolean(state, -1) != 0;
        lua.setTop(state, top);
        if (!applied) {
            lan::Frame neutral;
            neutral.players = session->players();
            neutral.connected = session->connectedMask();
            input::apply(neutral);
            originalUpdate(game);
            rooms::finishFrame();
            pendingHalf = false;
            return;
        }
        input::setMenuOwner(packet->pauseOwner);
        if ((*reinterpret_cast<int*>(g + 0x23a74) != 0) != packet->paused) {
            lan::Frame toggle;
            toggle.players = session->players();
            toggle.connected = packet->connected;
            toggle.inputs[packet->pauseOwner].values[12] = 65535;
            toggle.inputs[packet->pauseOwner].triggered = 1u << 12;
            input::apply(toggle);
            originalControls();
        }
        authoritative = std::move(packet);
        replicaPending.reset();
        session->applied(currentTick);
        committedView = true;
    }
    lan::Frame presentation;
    presentation.players = session->players();
    presentation.connected = session->connectedMask();
    input::apply(presentation);
    originalUpdate(game);
    rooms::finishFrame();
    if (committedView)
        integrationCallback("_IsaacLanViewCommitted");
    // Player interpolation also performs gameplay in this engine. Replicas
    // use the presentation callback instead of running that native simulation.
    pendingHalf = false;
}
void updateOne(void* game) {
    if (!gated) {
        originalUpdate(game);
        rooms::finishFrame();
        return;
    }
    if (replica() && session)
        if (const auto ending = session->takeEnding()) {
            playingEnding = true;
            input::reset();
            authoritative.reset();
            replicaPending.reset();
            rooms::playEnding(ending->id);
            writeProgress(ending->progress);
            if (logger)
                logger("ending_event=RECEIVED id=" + std::to_string(ending->id));
            return;
        }
    if (playingEnding) {
        // Keep the native cinematic/exit state machine alive after finish.
        // Returning directly to the lobby would skip the guest's ending.
        originalUpdate(game);
        rooms::finishFrame();
        return;
    }
    if (playingCinematic && session && session->phase() == lan::Phase::running) {
        session->poll();
        const auto manager =
            *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
        if (!cinematicReady) {
            originalUpdate(game);
            rooms::finishFrame();
            if (!*reinterpret_cast<bool*>(manager + 0x21618) &&
                *reinterpret_cast<int*>(manager + 8) == 2 && rooms::stateReady()) {
                cinematicReady = session->cinematicReady();
                if (logger)
                    logger("cinematic_event=READY");
            }
        }
        if (!session->cinematicActive()) {
            playingCinematic = cinematicReady = false;
            if (logger)
                logger("cinematic_event=COMPLETE");
        }
        return;
    }
    // Finish each accepted frame's interpolation/player phase exactly once,
    // even if the local renderer skipped its usual half-frame callback.
    if (pendingHalf) {
        if (logger)
            logger("half_late=" + std::to_string(currentTick));
        runHalf();
        // The manager restored foreground positions before entering this hook.
        // A deferred half update interpolated them again; undo that new
        // interpolation before beginning the next physical update.
        restorePositions();
    }
    if (session &&
        (session->phase() == lan::Phase::waiting || session->phase() == lan::Phase::closed)) {
        rooms::requestExit(false);
        return;
    }
    if (session && session->phase() == lan::Phase::failed) {
        authorizedExit = true;
        rooms::requestExit(session->isHost());
        return;
    }
    if (!session || session->phase() != lan::Phase::running)
        return;
    session->poll();
    if (!captureNextInput())
        return;
    session->poll();
    if (!session->isHost()) {
        updateReplica(game);
        return;
    }
    auto frame = session->take();
    if (!frame)
        return;
    // Later polls can receive the next controls before this frame is sent.
    // Acknowledgements describe the controls used by this simulation step.
    consumedInputSequences = session->inputSequences();
    const auto g = reinterpret_cast<std::uintptr_t>(game);
    const auto arrivals = frame->connected & ~rooms::connected();
    rooms::setConnected(frame->connected);
    rooms::protectArrivals(arrivals);
    integrationCallback("_IsaacLanActionStep");
    const auto requests = session->takeRoomRequests();
    for (unsigned slot = 1; slot < frame->players; ++slot)
        if (requests[slot]) {
            const bool accepted = rooms::receiveRoomRequest(slot, *requests[slot]);
            if (logger)
                logger("mod_room_command slot=" + std::to_string(slot) +
                       " accepted=" + std::to_string(accepted));
        }
    // A door transfer can finish while source-room input is still in flight.
    // Resume movement/items after the guest sees the destination. Held fire
    // must not become a release that discharges a charged weapon.
    const auto locations = rooms::captureLocations();
    for (unsigned slot = 1; slot < frame->players; ++slot) {
        const auto& context = frame->inputRooms[slot];
        if (!context || context->epoch != floorEpoch || slot >= locations.size() ||
            context->index != locations[slot].index ||
            context->dimension != locations[slot].dimension)
            frame->inputs[slot] = input::transitionInput(frame->inputs[slot],
                                                         context && context->epoch == floorEpoch);
        else
            presentation::observeIntro(slot, context->introSerial, context->introActive);
    }
    for (unsigned slot = 0; slot < frame->players; ++slot) {
        const auto command = frame->commands[slot];
        const bool paused = *reinterpret_cast<int*>(g + 0x23a74) != 0;
        if ((command == lan::Command::pause && !paused) ||
            (command == lan::Command::resume && paused && slot == input::menuOwner())) {
            frame->inputs[slot].values[12] = 65535;
            frame->inputs[slot].triggered |= 1u << 12;
        } else if (command == lan::Command::saveExit && slot == 0) {
            authorizedExit = true;
            rooms::requestExit(true);
        }
    }
    if (!(frame->connected & (1u << session->slot())))
        rooms::requestExit(false);
    input::apply(*frame);
    const int top = lua.getTop(state);
    lan::Writer packed(lan::Message::input);
    for (unsigned i = 0; i < frame->players; ++i)
        packed.input(frame->inputs[i]);
    lua.rawGetI(state, registry, applyRef);
    lua.pushInteger(state, frame->tick);
    lua.pushInteger(state, frame->players);
    lua.pushLString(state, reinterpret_cast<const char*>(packed.bytes.data() + 1),
                    packed.bytes.size() - 1);
    if (!call(applyRef, 3, 0, top)) {
        return;
    }
    currentTick = frame->tick;
    ++nextTick;
    originalControls();
    if (!gated) {
        return;
    }
    {
        presentation::IntroSimulationScope intro(true);
        originalUpdate(game);
    }
    presentation::items::advance();
    rooms::finishFrame();
    pendingHalf = gated && !playingCinematic;
}
void __attribute__((fastcall)) update(void* game, void*) {
    updateOne(game);
}
int host(lua_State* L) {
    const auto port = lua.checkInteger(L, 1);
    const char* fingerprint = lua.checkString(L, 2, nullptr);
    const char* mods = lua.checkString(L, 3, nullptr);
    if (session || port < 0 || port > 65535) {
        lua.pushBoolean(L, false);
        return 1;
    }
    session = std::make_unique<lan::Session>(logger);
    sessionFingerprint = fingerprint;
    lua.pushBoolean(L, session->host(static_cast<std::uint16_t>(port), fingerprint, mods));
    return 1;
}
int join(lua_State* L) {
    const char* ip = lua.checkString(L, 1, nullptr);
    const auto port = lua.checkInteger(L, 2);
    const char* fingerprint = lua.checkString(L, 3, nullptr);
    const char* mods = lua.checkString(L, 4, nullptr);
    if (session || port <= 0 || port > 65535) {
        lua.pushBoolean(L, false);
        return 1;
    }
    session = std::make_unique<lan::Session>(logger);
    sessionFingerprint = fingerprint;
    try {
        const auto path = archivePath().parent_path() / L"player-id.txt";
        std::string identity;
        std::ifstream file(path);
        if (file)
            file >> identity;
        const bool joined =
            session->join(ip, static_cast<std::uint16_t>(port), fingerprint, identity, mods);
        if (joined && identity.empty()) {
            std::filesystem::create_directories(path.parent_path());
            std::ofstream out(path, std::ios::trunc);
            out << session->identity() << '\n';
            if (!out)
                throw std::runtime_error("Cannot preserve local rejoin identity");
        }
        lua.pushBoolean(L, joined);
    } catch (const std::exception& error) {
        fail(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int poll(lua_State* L) {
    for (auto it = retiring.begin(); it != retiring.end();) {
        (*it)->poll();
        const auto phase = (*it)->phase();
        if (phase == lan::Phase::closed || phase == lan::Phase::failed) {
            if (logger)
                logger(phase == lan::Phase::closed ? "network_end=COMPLETE"
                                                   : "network_end=FAILED " + (*it)->error());
            it = retiring.erase(it);
        } else
            ++it;
    }
    if (session)
        session->poll();
    if (rejoinAt && InputClock::now() >= *rejoinAt) {
        rejoinAt.reset();
        if (session && !gated) {
            session->reconnect();
            if (logger)
                logger("network_return=RECONNECTING");
        }
    }
    // Service input at render frequency too. Waiting until the next 30 Hz game
    // update to send it needlessly adds a whole frame to a LAN round trip.
    if (gated && state == L) {
        input::pollPhysicalInput();
        if (captureNextInput())
            session->poll();
    }
    lua.createTable(L, 0, 8);
    auto integer = [&](const char* key, long long value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, key);
    };
    integer("phase", session ? static_cast<int>(session->phase()) : 0);
    integer("slot", session ? session->slot() : 0);
    integer("hosting", session && session->isHost());
    integer("modMismatch", session && session->modsDiffer());
    integer("players", session ? session->players() : 0);
    integer("connected", session ? session->connectedMask() : 0);
    integer("firstTick", session ? session->settings().firstTick : 0);
    integer("draining", retiring.size());
    integer("port", session ? session->port() : 0);
    integer("tick", nextTick);
    integer("verified", session && session->verifiedTick() ? *session->verifiedTick() : -1ll);
    const auto manager =
        *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
    integer("scene", manager ? *reinterpret_cast<int*>(manager + 8) : -1);
    lua.pushString(L, session ? session->error().c_str() : "");
    lua.setField(L, -2, "error");
    lua.pushString(L, session ? session->settings().seed.c_str() : "");
    lua.setField(L, -2, "seed");
    integer("difficulty", session ? session->settings().difficulty : 0);
    const auto game = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
    integer("pause", game ? *reinterpret_cast<int*>(game + 0x23a74) : 0);
    integer("pauseOwner", input::menuOwner());
    for (unsigned i = 0; i < 4; ++i)
        integer(("character" + std::to_string(i)).c_str(),
                session ? session->settings().characters[i] : 0);
    for (unsigned i = 0; i < 4; ++i) {
        integer(("choice" + std::to_string(i)).c_str(),
                session ? session->choices()[i].character : 0);
        integer(("ready" + std::to_string(i)).c_str(),
                session && session->choices()[i].ready ? 1 : 0);
        integer(("ping" + std::to_string(i)).c_str(), session ? session->latency()[i] : -1);
    }
    return 1;
}
int integrationInfo(lua_State* L) {
    lua.createTable(L, 0, 9);
    const bool active = !playingEnding && session && session->phase() == lan::Phase::running;
    auto integer = [&](const char* key, long long value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, key);
    };
    integer("active", active);
    integer("ready", active && gated && rooms::viewReady() && (session->isHost() || authoritative));
    integer("authority", active && session->isHost());
    integer("slot", session ? session->slot() : 0);
    integer("players", session ? session->players() : 0);
    integer("connected", session ? session->connectedMask() : 0);
    integer("worldEpoch", floorEpoch);
    integer("tick", currentTick);
    integer("nowMs", GetTickCount64());
    lua.pushString(L, session ? session->runId().c_str() : "");
    lua.setField(L, -2, "runId");
    return 1;
}
int integrationSend(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    std::size_t size = 0;
    const auto bytes = lua.checkString(L, 2, &size);
    bool sent = false;
    try {
        sent = session && slot >= 0 && slot < 4 && size <= lan::maxIntegrationSize &&
               session->sendIntegration(static_cast<unsigned>(slot), {bytes, size});
    } catch (const std::exception& error) {
        if (logger)
            logger(std::string("integration_send_error=") + error.what());
    }
    lua.pushBoolean(L, sent);
    return 1;
}
int integrationReceive(lua_State* L) {
    if (session)
        if (auto message = session->takeIntegration()) {
            lua.pushInteger(L, message->sender);
            lua.pushLString(L, message->bytes.data(), message->bytes.size());
            return 2;
        }
    return 0;
}
int start(lua_State* L) {
    const char* seed = lua.checkString(L, 1, nullptr);
    const auto difficulty = lua.checkInteger(L, 2);
    std::array<long long, 4> characters;
    for (unsigned i = 0; i < 4; ++i)
        characters[i] = lua.checkInteger(L, i + 3);
    if (!session || difficulty < 0 || difficulty > 3) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lan::Start settings;
    settings.seed = seed;
    settings.difficulty = static_cast<std::uint8_t>(difficulty);
    settings.progress = readProgress();
    for (unsigned i = 0; i < 4; ++i) {
        if (characters[i] < 0 || characters[i] > 65535) {
            lua.pushBoolean(L, false);
            return 1;
        }
        settings.characters[i] = static_cast<std::uint16_t>(characters[i]);
    }
    lua.pushBoolean(L, session->start(settings));
    return 1;
}
int choose(lua_State* L) {
    const auto character = lua.checkInteger(L, 1), ready = lua.checkInteger(L, 2);
    lua.pushBoolean(L, session && character >= 0 && character <= 65535 &&
                           (ready == 0 || ready == 1) &&
                           session->choose({static_cast<std::uint16_t>(character), ready != 0}));
    return 1;
}
int progressValues(lua_State* L) {
    const auto achievement = lua.checkInteger(L, 1), counter = lua.checkInteger(L, 2);
    const auto value = readProgress();
    if (achievement < 0 || achievement >= static_cast<long long>(value.achievements.size()) ||
        counter < 0 || counter >= static_cast<long long>(value.counters.size())) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lua.pushInteger(L, value.achievements[achievement]);
    lua.pushInteger(L, value.counters[counter]);
    return 2;
}
int startEngine(lua_State* L) {
    if (!session || session->phase() != lan::Phase::running || launchRequested || gated) {
        lua.pushBoolean(L, false);
        return 1;
    }
    // Seeds::String2Seed accepts the displayed nine-character form. Its input
    // is a read-only native small string, with no cross-runtime allocation.
    struct SmallString {
        char text[16]{};
        unsigned size = 9, capacity = 15;
    } value;
    const auto& settings = session->settings();
    std::memcpy(value.text, settings.seed.data(), 4);
    value.text[4] = ' ';
    std::memcpy(value.text + 5, settings.seed.data() + 4, 4);
    using ParseSeed = std::uint32_t(__cdecl*)(const SmallString*);
    const auto seed =
        reinterpret_cast<ParseSeed>(executableImage + j460::entry::runtimeNetParseSeed)(&value);
    if (!seed) {
        lua.pushBoolean(L, false);
        return 1;
    }
    SeedValue seeds{};
    using SeedConstructor = void(__attribute__((thiscall))*)(void*);
    using SetSeed = void(__attribute__((thiscall))*)(void*, std::uint32_t);
    reinterpret_cast<SeedConstructor>(executableImage +
                                      j460::entry::runtimeNetSeedConstructor)(&seeds);
    reinterpret_cast<SetSeed>(executableImage + j460::entry::runtimeNetSetSeed)(&seeds, seed);
    const auto manager = *reinterpret_cast<void**>(executableImage + j460::globals::manager);
    if (!beginNetworkRun()) {
        fail("Cannot preserve the existing solo save");
        lua.pushBoolean(L, false);
        return 1;
    }
    if (!settings.snapshot.empty()) {
        try {
            resumingArchive = lan::Archive::decode(settings.snapshot);
            if (resumingArchive->fingerprint != sessionFingerprint ||
                resumingArchive->locations.size() != session->players() ||
                resumingArchive->settings.seed != settings.seed ||
                !save::decode(executableImage, resumingArchive->game))
                throw std::runtime_error("Cannot restore host saved session");
        } catch (const std::exception& error) {
            fail(error.what());
            lua.pushBoolean(L, false);
            return 1;
        }
    }
    launchRequested = true;
    reinterpret_cast<StartGame>(executableImage + j460::entry::runtimeNetStartGame)(
        manager, settings.characters[0], 0, seeds, settings.difficulty);
    if (resumingArchive || (lua.getTop(L) > 0 && lua.checkInteger(L, 1) != 0)) {
        // Same continue request byte used by the native Continue menu. The
        // manager restores its GameState through Game::RestoreState itself.
        *reinterpret_cast<bool*>(reinterpret_cast<std::uintptr_t>(manager) + 0x4b131) = true;
        resumeLaunch = true;
    }
    if (logger)
        logger("network_engine_start=REQUESTED seed=" + std::to_string(seed));
    lua.pushBoolean(L, true);
    return 1;
}
int gate(lua_State* L) {
    if (gated || !session || session->phase() != lan::Phase::running || lua.type(L, 1) != 6 ||
        lua.type(L, 2) != 6 || lua.type(L, 3) != 6 || lua.type(L, 4) != 6 || lua.type(L, 5) != 6 ||
        lua.type(L, 6) != 6) {
        lua.pushBoolean(L, false);
        return 1;
    }
    state = L;
    lua.pushValue(L, 1);
    captureRef = lua.ref(L, registry);
    lua.pushValue(L, 2);
    applyRef = lua.ref(L, registry);
    lua.pushValue(L, 3);
    captureStateRef = lua.ref(L, registry);
    lua.pushValue(L, 4);
    restoreStateRef = lua.ref(L, registry);
    lua.pushValue(L, 5);
    presentRef = lua.ref(L, registry);
    lua.pushValue(L, 6);
    stageRef = lua.ref(L, registry);
    nextInputTick = 0;
    nextTick = currentTick = session->settings().firstTick;
    authoritative.reset();
    replicaPending.reset();
    floorEpoch = session->worldEpoch();
    localInput = {};
    lastInputRoom.reset();
    consumedInputSequences = {};
    captureCost = {};
    applyCost = {};
    nextCaptureAt = InputClock::now();
    pendingHalf = false;
    gated = true;
    playingEnding = false;
    playingCinematic = cinematicReady = false;
    session->ready();
    if (logger)
        logger(session->isHost() ? "state_authority=HOST" : "state_authority=REPLICA");
    lua.pushBoolean(L, true);
    return 1;
}
int close(lua_State* L) {
    const bool gameExit = lua.getTop(L) > 0 && lua.checkInteger(L, 1) == 1;
    const bool guestExit = gameExit && session && !session->isHost() && gated;
    const bool retry = guestExit && session->phase() == lan::Phase::failed;
    const bool keep = gameExit && session && (session->phase() == lan::Phase::waiting || retry);
    if (guestExit)
        frontend::returnToLobby();
    rejoinAt =
        retry ? std::optional{InputClock::now() + std::chrono::milliseconds(250)} : std::nullopt;
    // MC_PRE_GAME_EXIT runs before native Exit finishes saving/restoring its
    // co-op state. Keep the local baseline and serializer guard alive through
    // that tail; clearing them here lets shared progress be written afterward.
    if (!gameExit)
        restoreProgress();
    input::reset();
    if (session && !keep) {
        if (gated && session->phase() == lan::Phase::running) {
            session->finish();
            retiring.push_back(std::move(session));
        } else
            session->close();
    }
    gated = pendingHalf = false;
    playingEnding = false;
    playingCinematic = cinematicReady = false;
    for (int reference :
         {captureRef, applyRef, captureStateRef, restoreStateRef, presentRef, stageRef})
        if (reference >= 0)
            lua.unref(L, registry, reference);
    captureRef = applyRef = captureStateRef = restoreStateRef = presentRef = stageRef = -2;
    authoritative.reset();
    replicaPending.reset();
    floorEpoch = 0;
    lastInputRoom.reset();
    if (!keep) {
        session.reset();
        input::leaveLan();
    }
    state = nullptr;
    launchRequested = false;
    resumeLaunch = false;
    return 0;
}
int exitEngine(lua_State* L) {
    const bool save = lua.checkInteger(L, 1) != 0;
    if (!gated || !session || session->phase() != lan::Phase::running) {
        lua.pushBoolean(L, false);
        return 1;
    }
    rooms::requestExit(save);
    authorizedExit = true;
    lua.pushBoolean(L, true);
    return 1;
}
int savedState(lua_State* L) {
    if (lua.getTop(L) == 0) {
        const auto bytes = save::encode(executableImage);
        lua.pushLString(L, reinterpret_cast<const char*>(bytes.data()), bytes.size());
        return 1;
    }
    std::size_t size = 0;
    const char* bytes = lua.checkString(L, 1, &size);
    lua.pushBoolean(
        L, save::decode(executableImage, {reinterpret_cast<const std::uint8_t*>(bytes), size}));
    return 1;
}
int progressState(lua_State* L) {
    if (lua.getTop(L) == 0) {
        lan::Writer bytes(lan::Message::world);
        bytes.progress(readProgress());
        lua.pushLString(L, reinterpret_cast<const char*>(bytes.bytes.data() + 1),
                        bytes.bytes.size() - 1);
        return 1;
    }
    try {
        std::size_t size = 0;
        const auto data = lua.checkString(L, 1, &size);
        lan::Reader bytes({reinterpret_cast<const std::uint8_t*>(data), size});
        const auto progress = bytes.progress();
        bytes.finish();
        if (!replica() || !progress)
            throw std::runtime_error("Invalid progression replica");
        writeProgress(*progress);
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        fail(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
int resumeSession(lua_State* L) {
    const auto saved = readArchive();
    if (!session || !session->isHost() || !saved || saved->fingerprint != sessionFingerprint ||
        saved->locations.size() != session->players()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto settings = saved->settings;
    settings.snapshot = saved->encode();
    lua.pushBoolean(L, session->start(settings));
    return 1;
}
int restoreRooms(lua_State* L) {
    if (!resumingArchive) {
        lua.pushBoolean(L, true);
        return 1;
    }
    const bool ok = rooms::restoreLocations(resumingArchive->locations);
    if (ok) {
        rooms::setConnected(session->connectedMask());
        resumingArchive.reset();
    }
    lua.pushBoolean(L, ok);
    return 1;
}
int savedInfo(lua_State* L) {
    const auto saved = readArchive();
    lua.pushInteger(L, saved ? saved->locations.size() : 0);
    return 1;
}
lan::Archive captureCheckpoint() {
    lan::Archive archive;
    archive.fingerprint = sessionFingerprint;
    archive.settings = session->settings();
    archive.settings.snapshot.clear();
    archive.settings.progress = readProgress();
    archive.locations = rooms::captureLocations();
    for (unsigned slot = 1; slot < archive.locations.size(); ++slot)
        if (!(session->connectedMask() & (1u << slot)))
            archive.locations[slot] = archive.locations[0];
    if (!rooms::withCheckpointRoster([&] { archive.game = save::capture(executableImage); }) ||
        archive.game.empty())
        throw std::runtime_error("Cannot capture current-floor checkpoint");
    return archive;
}
int epoch(lua_State* L) {
    lua.pushInteger(L, floorEpoch);
    return 1;
}
int sharedCommand(lua_State* L) {
    const auto command = lua.checkInteger(L, 1);
    lua.pushBoolean(L, session && command >= 1 && command <= 4 &&
                           session->command(static_cast<lan::Command>(command)));
    return 1;
}
using ExecuteMenu = void(__attribute__((thiscall)) *)(void*);
ExecuteMenu originalExecuteMenu;
void __attribute__((fastcall)) executeMenu(void* manager, void*) {
    const auto m = reinterpret_cast<std::uintptr_t>(manager);
    const auto g = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
    if (gated && session && session->phase() == lan::Phase::running && !authorizedExit &&
        *reinterpret_cast<bool*>(m + 0x4b288) && *reinterpret_cast<int*>(m + 0x4b28c) == 2 && g &&
        *reinterpret_cast<int*>(g + 0x23a74) > 0 && input::menuOwner() != 0) {
        *reinterpret_cast<bool*>(m + 0x4b288) = false;
        if (session->slot() == input::menuOwner())
            session->command(lan::Command::leave);
        return;
    }
    originalExecuteMenu(manager);
}
} // namespace
void beforeExit(bool save) {
    exitingHost = session && session->isHost() && gated;
    exitingArchive.reset();
    if (!exitingHost || !save)
        return;
    lan::Archive archive;
    archive.fingerprint = sessionFingerprint;
    archive.settings = session->settings();
    archive.settings.snapshot.clear();
    archive.settings.progress = readProgress();
    archive.locations = rooms::captureLocations();
    exitingArchive = std::move(archive);
}
void afterExit(bool save) {
    if (!networkRun)
        return;
    restoreProgress();
    const bool host = exitingHost;
    exitingHost = false;
    try {
        const auto path = archivePath();
        if (host && !save)
            std::filesystem::remove(path);
        if (host && save) {
            if (!exitingArchive || exitingArchive->locations.size() < 2)
                throw std::runtime_error("No room state to save");
            exitingArchive->game = save::encode(executableImage);
            if (exitingArchive->game.empty())
                throw std::runtime_error("Native game save failed");
            writeArchive(*exitingArchive);
        }
    } catch (const std::exception& error) {
        if (logger)
            logger("session_save=FAILED " + std::string(error.what()));
    }
    exitingArchive.reset();
    const auto manager =
        *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::manager);
    if (!soloState.empty()) {
        if (!save::decode(executableImage, soloState) && logger)
            logger("solo_restore=FAILED");
    } else {
        using Clear = void(__attribute__((thiscall))*)(void*);
        reinterpret_cast<Clear>(executableImage + j460::entry::runtimeNetClear)(
            reinterpret_cast<void*>(manager + 0xfa4));
    }
    *reinterpret_cast<bool*>(manager + 0x20dcc) = soloContinueAvailable;
    soloState.clear();
    networkRun = false;
    authorizedExit = false;
    if (logger)
        logger("solo_save=RESTORED");
}
bool install(std::uintptr_t image, void (*log)(const std::string&), void (*halfUpdate)(),
             void (*restore)()) {
    executableImage = image;
    logger = log;
    runHalf = halfUpdate;
    restorePositions = restore;
    auto hook = [](std::uintptr_t target, void* replacement, void** original) {
        return MH_CreateHook(reinterpret_cast<void*>(target), replacement, original) == MH_OK &&
               MH_EnableHook(reinterpret_cast<void*>(target)) == MH_OK;
    };
    return hook(image + j460::entry::managerSave, reinterpret_cast<void*>(saveGame),
                reinterpret_cast<void**>(&originalSaveGame)) &&
           hook(image + j460::entry::managerDeleteSave, reinterpret_cast<void*>(deleteGame),
                reinterpret_cast<void**>(&originalDeleteGame)) &&
           hook(image + j460::entry::managerSaveRerun, reinterpret_cast<void*>(saveRerun),
                reinterpret_cast<void**>(&originalSaveRerun)) &&
           hook(image + j460::entry::managerExecuteMenu, reinterpret_cast<void*>(executeMenu),
                reinterpret_cast<void**>(&originalExecuteMenu)) &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::progressSerialize),
                         reinterpret_cast<void*>(serializeProgress),
                         reinterpret_cast<void**>(&originalSerializeProgress)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::progressSerialize)) ==
               MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::gameStart),
                         reinterpret_cast<void*>(startGame),
                         reinterpret_cast<void**>(&originalStart)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::gameStart)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::managerExecuteStart),
                         reinterpret_cast<void*>(executeStart),
                         reinterpret_cast<void**>(&originalExecuteStart)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::managerExecuteStart)) ==
               MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::gameUpdate),
                         reinterpret_cast<void*>(update),
                         reinterpret_cast<void**>(&originalUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::gameUpdate)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::consoleUpdate),
                         reinterpret_cast<void*>(consoleUpdate),
                         reinterpret_cast<void**>(&originalConsoleUpdate)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::consoleUpdate)) == MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::consoleRunCommand),
                         reinterpret_cast<void*>(consoleCommand),
                         reinterpret_cast<void**>(&originalConsoleCommand)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::consoleRunCommand)) ==
               MH_OK &&
           MH_CreateHook(reinterpret_cast<void*>(image + j460::entry::gameControls),
                         reinterpret_cast<void*>(controls),
                         reinterpret_cast<void**>(&originalControls)) == MH_OK &&
           MH_EnableHook(reinterpret_cast<void*>(image + j460::entry::gameControls)) == MH_OK;
}
bool halfAllowed() {
    // Retain native arrival interpolation while room replication is suspended.
    return !gated || playingEnding || playingCinematic || pendingHalf ||
           (replica() && !rooms::stateReady());
}
bool replica() {
    return gated && session && !session->isHost();
}
unsigned difficulty() {
    return session ? session->settings().difficulty : 0;
}
bool ending() {
    return playingEnding;
}
std::uint32_t worldEpoch() {
    return floorEpoch;
}
void present() {
    if (!replica() || !state || presentRef < 0 || session->phase() != lan::Phase::running ||
        !rooms::stateReady())
        return;
    // SwapBuffers is too late: the next Game::Update would overwrite the
    // predicted position before drawing it. Present after native updates and
    // immediately before Game::Render, for both ordinary and half frames.
    input::pollPhysicalInput();
    if (!captureNextInput())
        return;
    const int top = lua.getTop(state);
    lua.rawGetI(state, registry, presentRef);
    lan::Writer packed(lan::Message::input);
    packed.input(input::previewPhysicalInput());
    lua.pushLString(state, reinterpret_cast<const char*>(packed.bytes.data() + 1),
                    packed.bytes.size() - 1);
    // Movement displayed between network samples belongs to the upcoming
    // input, not the last sent sample (which the host may already acknowledge).
    lua.pushInteger(state, nextInputTick);
    if (call(presentRef, 2, 0, top))
        rooms::presentCamera();
}
void refreshAutomation(std::uint32_t renderFrame) {
    if (!state || !gated || !session || session->phase() != lan::Phase::running) {
        input::clearAutomation();
        return;
    }
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanBotFrame") == 6) {
        lua.pushInteger(state, renderFrame);
        if (lua.pcall(state, 1, 0, 0, 0, nullptr)) {
            input::clearAutomation();
            if (logger) {
                const auto reason = lua.toString(state, -1, nullptr);
                logger(std::string("lanbot_error=") + (reason ? reason : "Lua error"));
            }
        }
    } else
        input::clearAutomation();
    lua.setTop(state, top);
}
void pollLocalConsole() {
    if (!gated || !session || session->phase() != lan::Phase::running || !originalConsoleUpdate)
        return;
    const auto game = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
    if (game)
        originalConsoleUpdate(reinterpret_cast<void*>(game + 0x68d78));
}
void beginStage(bool same, int animation, bool rKey, unsigned cinematic) {
    if (!gated || !session || !session->isHost() || session->phase() != lan::Phase::running)
        return;
    const auto game = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
    lan::Stage value;
    ++floorEpoch;
    value.epoch = floorEpoch;
    value.level = *reinterpret_cast<int*>(game);
    value.type = *reinterpret_cast<int*>(game + 4);
    value.same = same;
    value.animation = animation;
    value.rKey = rKey;
    if (rKey) {
        value.level = 1;
        value.type = 0;
    }
    std::memcpy(value.seeds.data(), reinterpret_cast<void*>(game + 0x1bb84), sizeof(value.seeds));
    std::memcpy(value.stateFlags.data(), reinterpret_cast<void*>(game + 0x26548),
                sizeof(value.stateFlags));
    value.cinematic = cinematic;
    if (!session->beginStage(value)) {
        fail("Native floor transaction rejected");
        return;
    }
    playingCinematic = cinematic != 0;
    cinematicReady = false;
    if (playingCinematic) {
        input::reset();
        pendingHalf = false;
    }
    if (logger)
        logger("floor_event=SENT epoch=" + std::to_string(floorEpoch));
}
void prepareEnding() {
    playingEnding = true;
    input::reset();
    pendingHalf = false;
}
bool beginEnding(unsigned ending) {
    if (!gated || !session || !session->isHost() || session->phase() != lan::Phase::running ||
        !session->beginEnding(ending, readProgress()))
        return false;
    prepareEnding();
    if (logger)
        logger("ending_event=SENT id=" + std::to_string(ending));
    return true;
}
void beginRewind(std::span<const std::uint8_t> bytes) {
    if (!gated || !session || !session->isHost() || session->phase() != lan::Phase::running)
        return;
    const auto game = *reinterpret_cast<std::uintptr_t*>(executableImage + j460::globals::game);
    lan::Stage value;
    value.epoch = ++floorEpoch;
    value.level = *reinterpret_cast<int*>(game);
    value.type = *reinterpret_cast<int*>(game + 4);
    value.animation = 12;
    value.rewind.assign(bytes.begin(), bytes.end());
    session->beginStage(value);
    if (logger)
        logger("hourglass_event=SENT epoch=" + std::to_string(floorEpoch) +
               " bytes=" + std::to_string(bytes.size()));
}
bool requestRoom(const lan::RoomRequest& request) {
    // UI Mods request native transitions from a render callback, while their
    // local room is scoped for drawing. The host validates the source room;
    // snapshot readiness (which excludes scoped rooms) is unrelated here.
    return replica() && session->requestRoom(request);
}
std::uint32_t tick() {
    return currentTick;
}
int localViewSlot() {
    return gated && session ? static_cast<int>(session->slot()) : -1;
}
void requestWindowClose() {
    if (!gated || !session)
        return;
    if (session->phase() == lan::Phase::running)
        session->command(session->isHost() ? lan::Command::saveExit : lan::Command::leave);
    else {
        authorizedExit = true;
        rooms::requestExit(session->isHost());
    }
}
void abort(const std::string& error) {
    fail(error);
}
void roomEntered() {
    if (!replica())
        integrationCallback("_IsaacLanRoomEntered");
}
void halfStarted() {
    if (gated)
        input::finishUpdate();
}
void halfCompleted() {
    if (!gated || !pendingHalf || playingEnding)
        return;
    pendingHalf = false;
    if (session)
        session->completed(currentTick);
    if (session && session->isHost() && session->phase() == lan::Phase::running &&
        rooms::stateReady()) {
        rooms::takeFloorChange();
        try {
            if (session->checkpointNeeded()) {
                const auto checkpoint = captureCheckpoint();
                auto settings = session->settings();
                settings.snapshot = checkpoint.encode();
                settings.progress = readProgress();
                if (!session->checkpoint(settings, nextTick))
                    throw std::runtime_error("Cannot publish current-floor checkpoint");
            }
            integrationCallback("_IsaacLanViewCommitted");
            publishState();
        } catch (const std::exception& error) {
            fail(error.what());
        }
    } else if (rooms::stateReady())
        publishState();
}
bool bind(lua_State* L, HMODULE module) {
#define IMPORT(field, name)                                                                        \
    do {                                                                                           \
        auto pointer = GetProcAddress(module, name);                                               \
        static_assert(sizeof(pointer) == sizeof(lua.field));                                       \
        memcpy(&lua.field, &pointer, sizeof(pointer));                                             \
        if (!lua.field)                                                                            \
            return false;                                                                          \
    } while (false)
    IMPORT(pushClosure, "lua_pushcclosure");
    IMPORT(setField, "lua_setfield");
    IMPORT(createTable, "lua_createtable");
    IMPORT(pushInteger, "lua_pushinteger");
    IMPORT(pushBoolean, "lua_pushboolean");
    IMPORT(pushString, "lua_pushstring");
    IMPORT(pushLString, "lua_pushlstring");
    IMPORT(checkInteger, "luaL_checkinteger");
    IMPORT(checkString, "luaL_checklstring");
    IMPORT(toString, "lua_tolstring");
    IMPORT(getTop, "lua_gettop");
    IMPORT(getGlobal, "lua_getglobal");
    IMPORT(setTop, "lua_settop");
    IMPORT(pushValue, "lua_pushvalue");
    IMPORT(type, "lua_type");
    IMPORT(ref, "luaL_ref");
    IMPORT(unref, "luaL_unref");
    IMPORT(rawGetI, "lua_rawgeti");
    IMPORT(pcall, "lua_pcallk");
    IMPORT(boolean, "lua_toboolean");
#undef IMPORT
    auto function = [&](const char* name, LuaFunction fn) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    };
    function("api_info", integrationInfo);
    function("api_send", integrationSend);
    function("api_receive", integrationReceive);
    function("net_host", host);
    function("net_join", join);
    function("net_poll", poll);
    function("net_start", start);
    function("net_choose", choose);
    function("net_engine_start", startEngine);
    function("net_gate", gate);
    function("net_close", close);
    function("net_progress", progressState);
    function("progress_values", progressValues);
    function("net_engine_exit", exitEngine);
    function("net_saved_state", savedState);
    function("net_resume", resumeSession);
    function("net_restore_rooms", restoreRooms);
    function("net_saved_info", savedInfo);
    function("net_command", sharedCommand);
    function("net_floor_epoch", epoch);
    return true;
}
} // namespace isaac::runtime

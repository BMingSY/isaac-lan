#include "engine/lua_api.h"
#include "runtime/session.h"
#include "runtime/session_state.h"
#include "runtime/session_store.h"
#include "runtime/input_schedule.h"
#include "compat/challenges/catalog.h"
#include "engine/characters.h"
#include "engine/item_presentation.h"
#include "engine/presentation.h"
#include "engine/frontend.h"
#include "net/session.h"
#include "engine/rooms.h"
#include "engine/rewind.h"
#include "engine/input.h"
#include "core/lanbot_console.h"
#include "core/menu_input.h"
#include "core/chat.h"
#include "engine/save.h"
#include "runtime/session_archive.h"
#include "runtime/pending_archive.h"
#include "runtime/progression.h"
#include "diagnostics/runtime_log.h"
#include "diagnostics/performance.h"
#include "engine/session_backend.h"
#include <cstring>
#include <filesystem>
#include <fstream>
#include <chrono>

namespace backend = isaac::engine::session;

namespace isaac::runtime {
namespace {
constexpr int registry = -1001000;
using LuaFunction = int(__cdecl*)(lua_State*);
isaac::lua::API lua{};
std::unique_ptr<lan::Session> session;
std::vector<std::unique_ptr<lan::Session>> retiring;
std::uintptr_t executableImage = 0;
void (*logger)(const std::string&) = nullptr;
bool authorizedExit = false;
LaunchState launch;
SessionView view;
SavedRun saves;
std::string sessionFingerprint;
bool retryArchive();
lan::RunRules rulesFor(const compat::challenges::Definition* definition) {
    return definition ? lan::RunRules{definition->id, definition->version, definition->character,
                                      definition->difficulty, definition->transient}
                      : lan::RunRules{};
}
bool validRules(const lan::RunRules& rules) {
    const auto* definition = compat::challenges::find(rules.id);
    return (!rules.id || definition) && rules == rulesFor(definition);
}
bool beginNetworkRun() {
    if (saves.networkRun)
        return true;
    if (!retryArchive())
        return false;
    saves.soloContinueAvailable = backend::continueAvailable();
    saves.soloState =
        saves.soloContinueAvailable ? save::encode(executableImage) : std::vector<std::uint8_t>{};
    if (saves.soloContinueAvailable && saves.soloState.empty()) {
        if (logger)
            logger("solo_backup=FAILED");
        return false;
    }
    saves.networkRun = true;
    rooms::setConnected(lan::allPlayersMask);
    return true;
}
void saveGame(const backend::Call& original) {
    if (!saves.networkRun) {
        original();
        return;
    }
    // Capture also runs native player departure cleanup. The caller restores
    // room effects afterward, including Wooden Cross's remaining shields.
    // Preserve that pair on autosave as well as exit, while keeping the capture
    // in memory: only our separate session archive may be written for this run.
    backend::captureSave();
}
void deleteGame(const backend::Call& original) {
    if (!saves.networkRun) {
        original();
        return;
    }
    backend::suppressDelete();
}
void saveRerun(const backend::Call& original) {
    if (!saves.networkRun)
        original();
}
std::filesystem::path archivePath() {
    wchar_t executable[32768]{};
    GetModuleFileNameW(nullptr, executable, std::size(executable));
    const auto slot = backend::saveSlot();
    return std::filesystem::path(executable).parent_path() / L"isaac-lan" /
           (L"session-" + std::to_wstring(slot) + L".bin");
}
void writeArchive(const std::filesystem::path& path, const std::vector<std::uint8_t>& value) {
    const auto bytes = SessionStore(path).writeBytes(value);
    if (logger)
        logger("session_save=COMPLETE bytes=" + std::to_string(bytes));
}
bool retryArchive() {
    if (!saves.pendingArchive.pending())
        return true;
    const bool ok = saves.pendingArchive.retry(writeArchive);
    saves.saveError = ok ? "" : "联机存档保存失败，请重试保存";
    if (!ok && logger)
        logger("session_save=FAILED " + saves.pendingArchive.error());
    return ok;
}
int retrySavedArchive(lua_State* L) {
    lua.pushBoolean(L, retryArchive());
    return 1;
}
std::optional<lan::Archive> readArchive() {
    try {
        return SessionStore(archivePath()).read();
    } catch (const std::exception& error) {
        if (logger)
            logger("session_read=FAILED " + std::string(error.what()));
        return {};
    }
}
lan::Progress readProgress() {
    return backend::readProgress();
}
lan::LobbyAccess personalAccess() {
    // Embedded modules load during Lua initialization, before the native save
    // manager exists. Access is unavailable until that initialization finishes.
    if (!backend::managerReady())
        return {};
    // During a shared run native progress contains the host's values. Access
    // always comes from this player's save, captured before that substitution.
    const auto progress = saves.localProgress ? *saves.localProgress : readProgress();
    lan::LobbyAccess access;
    for (const auto& entry : characters::catalogue(executableImage, progress).entries) {
        if (entry.selectable)
            access.characters.push_back(entry.type);
        if (entry.unlocked)
            access.unlockedCharacters.push_back(entry.type);
    }
    std::sort(access.characters.begin(), access.characters.end());
    std::sort(access.unlockedCharacters.begin(), access.unlockedCharacters.end());
    for (const auto& definition : compat::challenges::definitions)
        if (compat::challenges::available(definition, progress.achievements))
            access.rules.push_back({definition.id, definition.version});
    return access;
}
void writeProgress(const lan::Progress& value) {
    backend::writeProgress(value);
}
void restoreProgress() {
    if (!saves.localProgress || !saves.commonProgress)
        return;
    const auto current = readProgress();
    // Keep each user's previous progress. Only changes earned during this
    // shared run are merged back; the host's old achievements are not granted.
    writeProgress(lan::mergeProgress(*saves.localProgress, *saves.commonProgress, current));
    saves.localProgress.reset();
    saves.commonProgress.reset();
}
void serializeProgress(const backend::Call& original) {
    if (!saves.localProgress || !saves.commonProgress) {
        original();
        return;
    }
    const auto current = readProgress();
    writeProgress(lan::mergeProgress(*saves.localProgress, *saves.commonProgress, current));
    original();
    writeProgress(current);
    if (logger)
        logger("progress_save=ISOLATED");
}
lua_State* state = nullptr;
int captureRef = -2, applyRef = -2, captureStateRef = -2, restoreStateRef = -2, presentRef = -2,
    stageRef = -2;
lan::InputFrame localInput;
std::optional<lan::InputRoom> lastInputRoom;
std::uint32_t nextInputTick = 0;
using InputClock = std::chrono::steady_clock;
InputSchedule inputSchedule;
unsigned inputHz = 60;
std::optional<InputClock::time_point> rejoinAt;
std::uint32_t nextTick = 0, currentTick = 0;
std::array<std::uint32_t, lan::maxPlayers> consumedInputSequences{};
struct StateCost {
    unsigned samples = 0;
    double total = 0, maximum = 0;
    void sample(InputClock::time_point start, const char* operation) {
        if (!logging::enabled(logging::Level::debug) && !diagnostics::enabled())
            return;
        const double ms =
            std::chrono::duration<double, std::milli>(InputClock::now() - start).count();
        diagnostics::sample(operation, ms);
        ++samples;
        total += ms;
        maximum = std::max(maximum, ms);
        if (samples == 300) {
            if (logger && logging::enabled(logging::Level::debug))
                logger(std::string("state_cost operation=") + operation + " mean_ms=" +
                       std::to_string(total / samples) + " max_ms=" + std::to_string(maximum));
            samples = 0;
            total = maximum = 0;
        }
    }
} captureCost, applyCost;
void (*runHalf)() = nullptr;
void (*restorePositions)() = nullptr;
void consoleCommand(std::string_view command, const backend::Call& original) {
    if (const auto args = input::consoleArguments(command, "rewind");
        args && view.gated && session && session->phase() == lan::Phase::running) {
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
    original();
}
void consoleUpdate(const backend::Call& original) {
    // LAN services this local interface once per render, independently of the
    // host's 30 Hz simulation and the guest's snapshot presentation.
    if (!view.gated || !session || session->phase() != lan::Phase::running)
        original();
}
void controls(const backend::Call& original) {
    if (!view.gated || view.playingEnding || view.playingCinematic) {
        original();
        return;
    }
    if (!session || session->phase() != lan::Phase::running || backend::pause() == 0)
        return;
    // Losing focus can open a native menu on a guest without pausing the
    // authority. Clear that local overlay even before another snapshot arrives.
    if (!session->isHost() && view.authoritative && !view.authoritative->paused) {
        rooms::withView([&] { pause_menu::synchronize(executableImage, false); }, true);
        return;
    }
    input::PauseScope inputScope(session->slot());
    rooms::withView([&] { pause_menu::controls(executableImage); }, true);
    const auto request = inputScope.intent();
    if (request == pause_menu::Intent::resume && session->slot() == input::menuOwner())
        session->command(lan::Command::resume);
    else if (request == pause_menu::Intent::exit)
        session->command(session->isHost() ? lan::Command::saveExit : lan::Command::leave);
}
void fail(const std::string& error);
lan::Archive captureCheckpoint();
void executeStart(const backend::Call& original) {
    const bool resume = launch.resume && session && session->phase() == lan::Phase::running;
    if (resume) {
        rooms::beforeStart();
        input::reset();
        // Hotplug IDs can change after returning to the menu. Native Continue
        // drops players whose saved controller is absent, before Lua can bind
        // them. Restore LAN device IDs before that roster is reconstructed.
        input::prepareControllers();
        if (session->settings().progress && !saves.localProgress) {
            saves.localProgress = readProgress();
            saves.commonProgress = session->settings().progress;
            writeProgress(*saves.commonProgress);
        }
    }
    original();
    // Manager invokes ExecuteStart every frame, even without a queued launch.
    // Reset only after an actual new/continued run, preserving later prompts.
    if ((launch.promptsPending || resume) && session && session->phase() == lan::Phase::running)
        input::resetMenuPrompts();
    launch.promptsPending = false;
    if (resume) {
        // Continue restores players before our controller assignment callback.
        // Clear the native reconnect/pause screen once every controller is
        // bound, just as the new-run path initializes PauseScreen.
        backend::resetPause();
        launch.resume = false;
    }
}
void startGame(const backend::Call& original) {
    rooms::beforeStart();
    input::reset();
    const bool networkStart = session && session->phase() == lan::Phase::running;
    if (networkStart && !beginNetworkRun()) {
        session->abort("Cannot preserve the existing solo save");
        return;
    }
    if (networkStart && session->settings().progress && !saves.localProgress) {
        saves.localProgress = readProgress();
        saves.commonProgress = session->settings().progress;
        writeProgress(*saves.commonProgress);
    }
    original();
    if (networkStart)
        launch.promptsPending = true;
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
    if (!state || !view.gated || !session)
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
        packet.paused = backend::pause() != 0;
        packet.pauseOwner = input::menuOwner();
        packet.inputSequences = consumedInputSequences;
        packet.bytes.assign(bytes, bytes + size);
        session->publish(slot, packet);
        lua.setTop(state, top);
    }
    session->poll();
}
bool captureNextInput(bool simulationStep = false) {
    if (!view.gated || !session || view.playingEnding || view.playingCinematic ||
        session->phase() != lan::Phase::running)
        return false;
    // Host input belongs to each native simulation step. Guest input follows
    // the native input frames (normally 60 Hz), without a second wall-clock
    // timer that can miss a frame or delay a press/release by another 33 ms.
    const auto frame = input::physicalFrame();
    if (!inputSchedule.capture(session->isHost(), simulationStep, frame))
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
    if (backend::pause() != 0)
        localInput = input::pausedInput(localInput);
    std::optional<lan::InputRoom> inputRoom;
    const auto locations = rooms::captureLocations();
    if (rooms::stateReady() && session->slot() < locations.size()) {
        const auto& position = locations[session->slot()];
        inputRoom = lan::InputRoom{view.floorEpoch, static_cast<std::int16_t>(position.index),
                                   static_cast<std::uint8_t>(position.dimension)};
        inputRoom->introSerial = presentation::playedIntro();
        inputRoom->introActive = presentation::introActive();
    }
    input::captureRoomInput(localInput, inputRoom, lastInputRoom, view.floorEpoch);
    if (!session->submit(nextInputTick, localInput, inputRoom)) {
        fail("Local input sequence rejected");
        return false;
    }
    ++nextInputTick;
    return true;
}
bool applyReplicaView(bool betweenUpdates) {
    // Reliable transitions, initial loading, and modal changes retain the full
    // update path. A half frame only restores a ready, stable world view.
    if (betweenUpdates && (!view.authoritative || view.playingEnding || view.playingCinematic ||
                           !rooms::stateReady() || session->phase() != lan::Phase::running ||
                           session->worldEpoch() != view.floorEpoch))
        return false;
    if (auto packet = session->takeState())
        view.replicaPending = std::move(packet);
    if (view.replicaPending) {
        auto& packet = view.replicaPending;
        if (betweenUpdates && (packet->paused != view.authoritative->paused ||
                               packet->connected != view.authoritative->connected))
            return false;
        const int top = lua.getTop(state);
        lua.rawGetI(state, registry, restoreStateRef);
        const auto began = InputClock::now();
        lua.pushLString(state, reinterpret_cast<const char*>(packet->bytes.data()),
                        packet->bytes.size());
        lua.pushInteger(state, packet->tick);
        lua.pushInteger(state, packet->inputSequences[session->slot()]);
        lua.pushBoolean(state, betweenUpdates);
        if (!call(restoreStateRef, 4, 1, top))
            return false;
        applyCost.sample(began, "apply");
        // A valid new-floor snapshot can arrive while the native transition is
        // still running. Keep the newest view and retry after initialization.
        const bool applied = lua.type(state, -1) != 1 || lua.toBoolean(state, -1) != 0;
        lua.setTop(state, top);
        if (!applied)
            return false;
        currentTick = packet->tick;
        nextTick = currentTick + 1;
        input::setMenuOwner(packet->pauseOwner);
        pause_menu::selectPlayer(executableImage, session->slot());
        if (packet->paused != (pause_menu::state(executableImage).page != 0))
            rooms::withView([&] { pause_menu::synchronize(executableImage, packet->paused); },
                            true);
        view.authoritative = std::move(packet);
        view.replicaPending.reset();
        session->applied(currentTick);
        return true;
    }
    return false;
}
void updateReplica(const backend::Call& original) {
    // A faster host can finish another floor while this replica is still
    // initializing the previous one. Leave the reliable event in the session
    // until the native roster is ready; keep updating the loading floor below.
    if (auto transition = rooms::stateReady() ? session->takeStage() : std::nullopt) {
        view.replicaPending.reset();
        view.authoritative.reset();
        // A returning client may still have its actor parked according to the
        // checkpoint roster. The readiness event admits this local controller
        // before a deferred native floor event can name its player object.
        rooms::setConnected(session->connectedMask() | (1u << session->slot()));
        view.floorEpoch = transition->epoch;
        // Native Forget Me Now, five-pip rooms and R Key update Seeds before
        // starting the transition. A stage number alone regenerates the old
        // client topology, whose missing descriptor can crash the minimap.
        if (transition->rewind.empty())
            backend::applyStage(*transition);
        const int top = lua.getTop(state);
        lua.rawGetI(state, registry, stageRef);
        lua.pushInteger(state, transition->epoch);
        lua.pushInteger(state, transition->level);
        lua.pushInteger(state, transition->type);
        lua.pushInteger(state, transition->animation);
        lua.pushBoolean(state, transition->same);
        lua.pushLString(state, reinterpret_cast<const char*>(transition->rewind.data()),
                        transition->rewind.size());
        lua.pushInteger(state, transition->restart);
        lua.pushInteger(state, transition->cinematic);
        lua.pushInteger(state, transition->sourceRoom);
        view.playingCinematic = transition->cinematic != 0;
        view.cinematicReady = false;
        if (view.playingCinematic) {
            input::reset();
            view.pendingHalf = false;
        }
        if (!call(stageRef, 9, 0, top))
            return;
        rooms::finishFrame();
        if (logger)
            logger("floor_event=RECEIVED epoch=" + std::to_string(view.floorEpoch));
    }
    if (view.playingCinematic)
        return;
    const bool committedView = applyReplicaView(false);
    if (session->phase() != lan::Phase::running)
        return;
    lan::Frame presentation;
    presentation.players = session->players();
    presentation.connected = session->connectedMask();
    input::apply(presentation);
    original();
    rooms::finishFrame();
    if (committedView)
        integrationCallback("_IsaacLanViewCommitted");
    // Player interpolation also performs gameplay in this engine. Replicas
    // use the presentation callback instead of running that native simulation.
    view.pendingHalf = false;
}
void playSessionEnding(unsigned ending, bool completed) {
    if (completed)
        rooms::finishChallenge();
    else
        rooms::playEnding(ending);
}
void updateOne(const backend::Call& original) {
    if (!view.gated) {
        original();
        rooms::finishFrame();
        return;
    }
    if (replica() && session)
        if (const auto ending = session->takeEnding()) {
            view.playingEnding = true;
            input::reset();
            view.authoritative.reset();
            view.replicaPending.reset();
            playSessionEnding(ending->id, ending->completed);
            writeProgress(ending->progress);
            if (logger)
                logger("ending_event=RECEIVED id=" + std::to_string(ending->id) +
                       " completed=" + std::to_string(ending->completed));
            return;
        }
    if (view.pendingChallengeFinish && session && session->isHost()) {
        const auto ending = *view.pendingChallengeFinish;
        view.pendingChallengeFinish.reset();
        if (beginEnding(ending, true))
            playSessionEnding(ending, true);
        return;
    }
    if (view.playingEnding) {
        // Keep the native cinematic/exit state machine alive after finish.
        // Returning directly to the lobby would skip the guest's ending.
        original();
        rooms::finishFrame();
        return;
    }
    if (view.playingCinematic && session && session->phase() == lan::Phase::running) {
        session->poll();
        if (!view.cinematicReady) {
            original();
            rooms::finishFrame();
            if (backend::cinematicFinished() && rooms::stateReady()) {
                view.cinematicReady = session->cinematicReady();
                if (logger)
                    logger("cinematic_event=READY");
            }
        }
        if (!session->cinematicActive()) {
            view.playingCinematic = view.cinematicReady = false;
            if (logger)
                logger("cinematic_event=COMPLETE");
        }
        return;
    }
    // Finish each accepted frame's interpolation/player phase exactly once,
    // even if the local renderer skipped its usual half-frame callback.
    if (view.pendingHalf) {
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
    if (!captureNextInput(true))
        return;
    session->poll();
    if (!session->isHost()) {
        updateReplica(original);
        return;
    }
    auto frame = session->take();
    if (!frame)
        return;
    // Later polls can receive the next controls before this frame is sent.
    // Acknowledgements describe the controls used by this simulation step.
    consumedInputSequences = session->inputSequences();
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
        if (!context || context->epoch != view.floorEpoch || slot >= locations.size() ||
            context->index != locations[slot].index ||
            context->dimension != locations[slot].dimension)
            frame->inputs[slot] = input::transitionInput(
                frame->inputs[slot], context && context->epoch == view.floorEpoch);
        else
            presentation::observeIntro(slot, context->introSerial, context->introActive);
    }
    bool resumePause = false;
    for (unsigned slot = 0; slot < frame->players; ++slot) {
        const auto command = frame->commands[slot];
        const bool paused = backend::pause() != 0;
        if (command == lan::Command::pause && !paused) {
            frame->inputs[slot].values[input::action::menuPause] = lan::maxInputValue;
            frame->inputs[slot].triggered |= 1u << input::action::menuPause;
        } else if (command == lan::Command::resume && paused && slot == input::menuOwner()) {
            resumePause = true;
        } else if (command == lan::Command::saveExit && slot == 0) {
            authorizedExit = true;
            rooms::requestExit(!session->settings().rules.transient);
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
    const bool paused = backend::pause() != 0;
    bool openPause = false;
    if (!paused)
        for (unsigned slot = 0; slot < frame->players; ++slot)
            if ((frame->connected & (1u << slot)) &&
                (frame->inputs[slot].triggered & (1u << input::action::menuPause)))
                openPause = true;
    if (openPause || resumePause)
        rooms::withView(
            [&] {
                if (openPause)
                    pause_menu::show(executableImage);
                else
                    pause_menu::hide(executableImage);
            },
            true);
    else if (!paused)
        backend::controls();
    if (!view.gated) {
        return;
    }
    {
        presentation::IntroSimulationScope intro(true);
        original();
    }
    presentation::items::advance();
    rooms::finishFrame();
    view.pendingHalf = view.gated && !view.playingCinematic;
}
void update(const backend::Call& original) {
    updateOne(original);
}
int host(lua_State* L) {
    const auto port = lua.checkInteger(L, 1);
    const char* fingerprint = lua.checkString(L, 2, nullptr);
    const char* mods = lua.checkString(L, 3, nullptr);
    if (session || port < 0 || port > 65535 || !retryArchive()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    session = std::make_unique<lan::Session>(logger,
                                             diagnostics::enabled() ? diagnostics::sample : nullptr,
                                             logging::enabled(logging::Level::debug));
    sessionFingerprint = fingerprint;
    lua.pushBoolean(
        L, session->host(static_cast<std::uint16_t>(port), fingerprint, mods, personalAccess()));
    return 1;
}
int join(lua_State* L) {
    const char* ip = lua.checkString(L, 1, nullptr);
    const auto port = lua.checkInteger(L, 2);
    const char* fingerprint = lua.checkString(L, 3, nullptr);
    const char* mods = lua.checkString(L, 4, nullptr);
    if (session || port <= 0 || port > 65535 || !retryArchive()) {
        lua.pushBoolean(L, false);
        return 1;
    }
    session = std::make_unique<lan::Session>(logger,
                                             diagnostics::enabled() ? diagnostics::sample : nullptr,
                                             logging::enabled(logging::Level::debug));
    sessionFingerprint = fingerprint;
    try {
        const auto path = archivePath().parent_path() / L"player-id.txt";
        std::string identity;
        std::ifstream file(path);
        if (file)
            file >> identity;
        const bool joined = session->join(ip, static_cast<std::uint16_t>(port), fingerprint,
                                          identity, mods, personalAccess());
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
    if (session && diagnostics::enabled()) {
        const auto resource = session->resources();
        diagnostics::counter("connections", resource.connections);
        diagnostics::counter("queued_bytes", resource.queuedBytes);
        diagnostics::counter("receive_capacity_bytes", resource.receiveCapacity);
        diagnostics::counter("pending_world_capacity_bytes", resource.worldBytes);
        diagnostics::counter("cached_world_bytes", resource.cachedWorldBytes);
        diagnostics::counter("world_in_flight_bytes", resource.inFlightBytes);
        diagnostics::counter("world_in_flight_states", resource.inFlightStates);
        diagnostics::counter("world_snapshots_total", resource.worldSnapshots);
        diagnostics::counter("world_delta_snapshots_total", resource.deltaSnapshots);
        diagnostics::counter("world_raw_bytes_total", resource.rawWorldBytes);
        diagnostics::counter("world_wire_bytes_total", resource.wireWorldBytes);
        diagnostics::counter("world_full_wire_bytes_total", resource.fullWorldBytes);
        diagnostics::counter("retiring_sessions", retiring.size());
    }
    if (rejoinAt && InputClock::now() >= *rejoinAt) {
        rejoinAt.reset();
        if (session && !view.gated) {
            session->reconnect();
            if (logger)
                logger("network_return=RECONNECTING");
        }
    }
    // Service input at render frequency too. Waiting until the next 30 Hz game
    // update to send it needlessly adds a whole frame to a LAN round trip.
    if (view.gated && state == L) {
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
    integer("pendingSave", saves.pendingArchive.pending());
    lua.pushString(L, saves.saveError.c_str());
    lua.setField(L, -2, "saveError");
    integer("port", session ? session->port() : 0);
    integer("tick", nextTick);
    integer("verified", session && session->verifiedTick() ? *session->verifiedTick() : -1ll);
    integer("scene", backend::scene());
    lua.pushString(L, session ? session->error().c_str() : "");
    lua.setField(L, -2, "error");
    lua.pushString(L, session ? session->settings().seed.c_str() : "");
    lua.setField(L, -2, "seed");
    integer("difficulty", session ? session->settings().difficulty : 0);
    integer("challenge", session ? session->rules().id : 0);
    integer("challengeVersion", session ? session->rules().version : 0);
    integer("pause", backend::pause());
    integer("pauseOwner", input::menuOwner());
    for (unsigned i = 0; i < lan::maxPlayers; ++i)
        integer(("character" + std::to_string(i)).c_str(),
                session ? session->settings().characters[i] : 0);
    for (unsigned i = 0; i < lan::maxPlayers; ++i) {
        integer(("choice" + std::to_string(i)).c_str(),
                session ? session->choices()[i].character : 0);
        integer(("ready" + std::to_string(i)).c_str(),
                session && session->choices()[i].ready ? 1 : 0);
        integer(("ping" + std::to_string(i)).c_str(), session ? session->latency()[i] : -1);
        lua.pushBoolean(L, session && i < session->players() &&
                               session->access()[i].allowsRules(session->rules()));
        lua.setField(L, -2, ("eligible" + std::to_string(i)).c_str());
    }
    return 1;
}
int phaseValues(lua_State* L) {
    lua.createTable(L, 0, lan::phaseValues.size());
    for (const auto& [name, value] : lan::phaseValues) {
        lua.pushInteger(L, static_cast<int>(value));
        lua.setField(L, -2, name);
    }
    return 1;
}
int commandValues(lua_State* L) {
    lua.createTable(L, 0, lan::commandValues.size());
    for (const auto& [name, value] : lan::commandValues) {
        lua.pushInteger(L, static_cast<int>(value));
        lua.setField(L, -2, name);
    }
    return 1;
}
int integrationInfo(lua_State* L) {
    lua.createTable(L, 0, 9);
    const bool active = !view.playingEnding && session && session->phase() == lan::Phase::running;
    auto integer = [&](const char* key, long long value) {
        lua.pushInteger(L, value);
        lua.setField(L, -2, key);
    };
    integer("active", active);
    integer("ready", active && view.gated && rooms::viewReady() &&
                         (session->isHost() || view.authoritative));
    integer("authority", active && session->isHost());
    integer("slot", session ? session->slot() : 0);
    integer("players", session ? session->players() : 0);
    integer("connected", session ? session->connectedMask() : 0);
    integer("worldEpoch", view.floorEpoch);
    integer("challenge", active ? session->settings().rules.id : 0);
    integer("challengeVersion", active ? session->settings().rules.version : 0);
    integer("restrictedBags", craftingBagViewTarget() != -1);
    integer("tick", currentTick);
    integer("nowMs", GetTickCount64());
    lua.pushString(L, session ? session->runId().c_str() : "");
    lua.setField(L, -2, "runId");
    return 1;
}
int sideChannelSend(lua_State* L, bool communication) {
    const auto slot = lua.checkInteger(L, 1);
    std::size_t size = 0;
    const auto bytes = lua.checkString(L, 2, &size);
    bool sent = false;
    try {
        if (session && slot >= 0 && slot < 4)
            sent = communication ? session->sendCommunication(slot, {bytes, size})
                                 : session->sendIntegration(slot, {bytes, size});
    } catch (const std::exception& error) {
        if (logger)
            logger(std::string("side_channel_send_error=") + error.what());
    }
    lua.pushBoolean(L, sent);
    return 1;
}
int sideChannelReceive(lua_State* L, bool communication) {
    if (session)
        if (auto message =
                communication ? session->takeCommunication() : session->takeIntegration()) {
            lua.pushInteger(L, message->sender);
            lua.pushLString(L, message->bytes.data(), message->bytes.size());
            return 2;
        }
    return 0;
}
int integrationSend(lua_State* L) {
    return sideChannelSend(L, false);
}
int integrationReceive(lua_State* L) {
    return sideChannelReceive(L, false);
}
int communicationSend(lua_State* L) {
    return sideChannelSend(L, true);
}
int communicationReceive(lua_State* L) {
    return sideChannelReceive(L, true);
}
int executeChatCommand(lua_State* L) {
    const auto slot = lua.checkInteger(L, 1);
    std::size_t length = 0;
    const auto data = lua.checkString(L, 2, &length);
    const std::string_view command(data, length);
    if (!session || !session->isHost() || session->phase() != lan::Phase::running || !view.gated ||
        !rooms::stateReady() || slot < 0 || slot >= lan::maxPlayers ||
        !(session->connectedMask() & (1u << slot)) || length > chat::maxCommandBytes ||
        !chat::boundaries(command))
        return 0;
    std::string result;
    if (const auto args = input::consoleArguments(command, "rewind")) {
        const bool ok =
            args->find_first_not_of(" \t\r\n") == std::string_view::npos && rewind::request(slot);
        result = ok ? "已请求房间回退" : "当前无法回退";
    } else if (!rooms::withPlayer(slot, [&] { result = backend::executeConsole(command); }))
        return 0;
    lua.pushLString(L, result.data(), result.size());
    return 1;
}
int challengeList(lua_State* L) {
    const auto access = session ? session->localAccess() : personalAccess();
    lua.createTable(L, 0, compat::challenges::definitions.size());
    for (const auto& def : compat::challenges::definitions) {
        lua.createTable(L, 0, 9);
        auto integer = [&](const char* key, long long value) {
            lua.pushInteger(L, value);
            lua.setField(L, -2, key);
        };
        integer("id", def.id);
        integer("version", def.version);
        integer("character", def.character);
        integer("difficulty", def.difficulty);
        integer("nextBag", def.nextBag);
        lua.pushBoolean(L, access.allowsRules(rulesFor(&def)));
        lua.setField(L, -2, "available");
        lua.pushBoolean(L, session ? session->rulesAvailable(rulesFor(&def))
                                   : access.allowsRules(rulesFor(&def)));
        lua.setField(L, -2, "team_available");
        lua.pushString(L, def.name.data());
        lua.setField(L, -2, "name");
        lua.pushString(L, def.route.data());
        lua.setField(L, -2, "route");
        lua.setField(L, -2, std::to_string(def.id).c_str());
    }
    return 1;
}
int characterList(lua_State* L) {
    characters::Catalogue catalogue;
    if (backend::managerReady())
        catalogue = characters::catalogue(
            executableImage, saves.localProgress ? *saves.localProgress : readProgress());
    lua.createTable(L, catalogue.entries.size(), 0);
    unsigned index = 0;
    for (const auto& entry : catalogue.entries) {
        if (session ? !session->localAccess().allowsCharacter(entry.type) : !entry.selectable)
            continue;
        lua.pushInteger(L, entry.type);
        lua.rawSetI(L, -2, ++index);
    }
    lua.createTable(L, 0, catalogue.entries.size());
    for (const auto& entry : catalogue.entries) {
        lua.createTable(L, 0, 5);
        for (const auto& [key, value] :
             {std::pair{"name", &entry.name}, std::pair{"animation", &entry.animation},
              std::pair{"portraitPath", &entry.portraitPath},
              std::pair{"portraitAnm2Path", &entry.portraitAnm2Path}}) {
            lua.pushLString(L, value->data(), value->size());
            lua.setField(L, -2, key);
        }
        lua.pushBoolean(L, entry.tainted);
        lua.setField(L, -2, "tainted");
        lua.setField(L, -2, std::to_string(entry.type).c_str());
    }
    return 2;
}
int selectChallenge(lua_State* L) {
    const auto id = lua.checkInteger(L, 1);
    const auto* definition = id >= 0 && id <= 65535 ? compat::challenges::find(id) : nullptr;
    lua.pushBoolean(L, session && (id == 0 || definition) &&
                           session->configureRules(rulesFor(definition)));
    return 1;
}
int finishChallenge(lua_State* L) {
    const auto* definition =
        session ? compat::challenges::find(session->settings().rules.id) : nullptr;
    const bool allowed = definition && view.gated && session->isHost() && !view.playingEnding &&
                         session->phase() == lan::Phase::running;
    if (allowed)
        view.pendingChallengeFinish = definition->ending;
    lua.pushBoolean(L, allowed);
    return 1;
}
int start(lua_State* L) {
    const char* seed = lua.checkString(L, 1, nullptr);
    const auto difficulty = lua.checkInteger(L, 2);
    std::array<long long, lan::maxPlayers> characters;
    for (unsigned i = 0; i < lan::maxPlayers; ++i)
        characters[i] = lua.checkInteger(L, i + 3);
    if (!session || difficulty < 0 || difficulty > 3) {
        lua.pushBoolean(L, false);
        return 1;
    }
    lan::Start settings;
    settings.rules = session->rules();
    if (!validRules(settings.rules)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    settings.seed = seed;
    settings.difficulty = static_cast<std::uint8_t>(difficulty);
    settings.progress = readProgress();
    for (unsigned i = 0; i < lan::maxPlayers; ++i) {
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
    if (!session || !validRules(session->settings().rules)) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (!session || session->phase() != lan::Phase::running || launch.requested || view.gated) {
        lua.pushBoolean(L, false);
        return 1;
    }
    const auto& settings = session->settings();
    const auto seed = backend::parseSeed(settings.seed);
    if (!seed) {
        lua.pushBoolean(L, false);
        return 1;
    }
    if (!beginNetworkRun()) {
        fail("Cannot preserve the existing solo save");
        lua.pushBoolean(L, false);
        return 1;
    }
    if (!settings.snapshot.empty()) {
        try {
            saves.resumingArchive = lan::Archive::decode(settings.snapshot);
            if (saves.resumingArchive->fingerprint != sessionFingerprint ||
                saves.resumingArchive->locations.size() != session->players() ||
                saves.resumingArchive->settings.seed != settings.seed ||
                saves.resumingArchive->settings.rules != settings.rules ||
                !save::decode(executableImage, saves.resumingArchive->game))
                throw std::runtime_error("Cannot restore host saved session");
        } catch (const std::exception& error) {
            fail(error.what());
            lua.pushBoolean(L, false);
            return 1;
        }
    }
    launch.requested = true;
    backend::start(seed, settings.characters[0], settings.difficulty);
    if (saves.resumingArchive || (lua.getTop(L) > 0 && lua.checkInteger(L, 1) != 0)) {
        // Same continue request byte used by the native Continue menu. The
        // manager restores its GameState through Game::RestoreState itself.
        backend::requestContinue();
        launch.resume = true;
    }
    if (logger)
        logger("network_engine_start=REQUESTED seed=" + std::to_string(seed));
    lua.pushBoolean(L, true);
    return 1;
}
int gate(lua_State* L) {
    if (view.gated || !session || session->phase() != lan::Phase::running || lua.type(L, 1) != 6 ||
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
    view.authoritative.reset();
    view.replicaPending.reset();
    view.floorEpoch = session->worldEpoch();
    localInput = {};
    lastInputRoom.reset();
    consumedInputSequences = {};
    captureCost = {};
    applyCost = {};
    inputSchedule = InputSchedule(inputHz);
    view.pendingHalf = false;
    view.gated = true;
    view.playingEnding = false;
    view.pendingChallengeFinish.reset();
    view.playingCinematic = view.cinematicReady = false;
    session->ready();
    if (logger)
        logger(session->isHost() ? "state_authority=HOST" : "state_authority=REPLICA");
    lua.pushBoolean(L, true);
    return 1;
}
int close(lua_State* L) {
    const bool gameExit = lua.getTop(L) > 0 && lua.checkInteger(L, 1) == 1;
    const bool guestExit = gameExit && session && !session->isHost() && view.gated;
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
        if (view.gated && session->phase() == lan::Phase::running) {
            session->finish();
            retiring.push_back(std::move(session));
        } else
            session->close();
    }
    view.stop();
    for (int reference :
         {captureRef, applyRef, captureStateRef, restoreStateRef, presentRef, stageRef})
        if (reference >= 0)
            lua.unref(L, registry, reference);
    captureRef = applyRef = captureStateRef = restoreStateRef = presentRef = stageRef = -2;
    view.clearSnapshots();
    lastInputRoom.reset();
    if (!keep) {
        session.reset();
        input::leaveLan();
    }
    state = nullptr;
    launch = {};
    return 0;
}
int exitEngine(lua_State* L) {
    const bool save = lua.checkInteger(L, 1) != 0;
    if (!view.gated || !session || session->phase() != lan::Phase::running) {
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
        saved->locations.size() != session->players() || session->rules().id != 0 ||
        saved->settings.rules.transient) {
        lua.pushBoolean(L, false);
        return 1;
    }
    auto settings = saved->settings;
    settings.snapshot = saved->encode();
    lua.pushBoolean(L, session->start(settings));
    return 1;
}
int restoreRooms(lua_State* L) {
    if (!saves.resumingArchive) {
        lua.pushBoolean(L, true);
        return 1;
    }
    const bool ok = rooms::restoreLocations(saves.resumingArchive->locations);
    if (ok) {
        rooms::setConnected(session->connectedMask());
        saves.resumingArchive.reset();
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
    lua.pushInteger(L, view.floorEpoch);
    return 1;
}
int sharedCommand(lua_State* L) {
    const auto command = lua.checkInteger(L, 1);
    lua.pushBoolean(L, session && command >= 1 && command <= 4 &&
                           session->command(static_cast<lan::Command>(command)));
    return 1;
}
int pauseMenuState(lua_State* L) {
    const auto value = pause_menu::state(executableImage);
    lua.createTable(L, 0, 4);
    for (const auto& [key, field] :
         {std::pair{"page", value.page}, std::pair{"selection", value.selection},
          std::pair{"controller", value.controller}, std::pair{"optionId", value.optionId}}) {
        lua.pushInteger(L, field);
        lua.setField(L, -2, key);
    }
    return 1;
}
void executeMenu(const backend::Call& original) {
    if (view.gated && session && session->phase() == lan::Phase::running && !authorizedExit &&
        backend::exitRequested() && backend::pause() > 0 && input::menuOwner() != 0) {
        backend::cancelExit();
        if (session->slot() == input::menuOwner())
            session->command(lan::Command::leave);
        return;
    }
    original();
}
} // namespace
void beforeExit(bool save) {
    saves.exitingHost = session && session->isHost() && view.gated;
    saves.exitingTransient = session && session->settings().rules.transient;
    saves.exitingArchive.reset();
    if (!saves.exitingHost || !save || saves.exitingTransient)
        return;
    lan::Archive archive;
    archive.fingerprint = sessionFingerprint;
    archive.settings = session->settings();
    archive.settings.snapshot.clear();
    archive.settings.progress = readProgress();
    archive.locations = rooms::captureLocations();
    saves.exitingArchive = std::move(archive);
}
void afterExit(bool save) {
    if (!saves.networkRun)
        return;
    restoreProgress();
    const bool host = saves.exitingHost;
    saves.exitingHost = false;
    try {
        const auto path = archivePath();
        if (host && !save && !saves.exitingTransient)
            std::filesystem::remove(path);
        if (host && save && !saves.exitingTransient) {
            if (!saves.exitingArchive || saves.exitingArchive->locations.size() < 2)
                throw std::runtime_error("No room state to save");
            saves.exitingArchive->game = save::encode(executableImage);
            if (saves.exitingArchive->game.empty())
                throw std::runtime_error("Native game save failed");
            saves.pendingArchive.retain(path, std::move(*saves.exitingArchive));
            retryArchive();
        }
    } catch (const std::exception& error) {
        if (logger)
            logger("session_save=FAILED " + std::string(error.what()));
        saves.saveError = "联机存档保存失败";
    }
    saves.exitingArchive.reset();
    if (!saves.soloState.empty()) {
        if (!save::decode(executableImage, saves.soloState) && logger)
            logger("solo_restore=FAILED");
    } else {
        backend::clearSave();
    }
    backend::continueAvailable(saves.soloContinueAvailable);
    saves.soloState.clear();
    saves.networkRun = false;
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
    return backend::install(image, {saveGame, deleteGame, saveRerun, serializeProgress,
                                    executeStart, startGame, update, consoleUpdate, consoleCommand,
                                    controls, executeMenu});
}
void configureInput(unsigned hz) {
    inputHz = hz;
    inputSchedule = InputSchedule(hz);
}
bool halfAllowed() {
    if (replica() && !view.playingEnding && !view.playingCinematic && rooms::stateReady() &&
        session->phase() == lan::Phase::running) {
        session->poll();
        if (captureNextInput()) {
            session->poll();
            if (applyReplicaView(true))
                integrationCallback("_IsaacLanViewCommitted");
            session->poll();
        }
    }
    // Retain native arrival interpolation while room replication is suspended.
    return !view.gated || view.playingEnding || view.playingCinematic || view.pendingHalf ||
           (replica() && !rooms::stateReady());
}
bool replica() {
    return view.gated && session && !session->isHost();
}
bool challengeActive() {
    return session && (session->phase() == lan::Phase::running || saves.networkRun) &&
           session->settings().rules.id != 0;
}
bool allowRoomEntry(unsigned slot, int fromDimension, int fromRoom, int dimension, int room,
                    bool teleport) {
    if (!challengeActive() || replica())
        return true;
    if (!state)
        return false;
    const int top = lua.getTop(state);
    if (lua.getGlobal(state, "_IsaacLanCanEnterRoom") != 6) {
        lua.setTop(state, top);
        return false;
    }
    for (auto value : {static_cast<int>(slot), fromDimension, fromRoom, dimension, room})
        lua.pushInteger(state, value);
    lua.pushBoolean(state, teleport);
    if (!call(0, 6, 1, top))
        return false;
    const bool allowed = lua.type(state, -1) == 1 && lua.toBoolean(state, -1);
    lua.setTop(state, top);
    return allowed;
}
std::array<int, 2> challengeDestination() {
    const auto* definition =
        challengeActive() ? compat::challenges::find(session->settings().rules.id) : nullptr;
    return definition ? std::array{definition->goalStage, definition->goalStageType}
                      : std::array{-1, -1};
}
int craftingBagViewTarget() {
    if (!challengeActive())
        return -1;
    const auto* definition = compat::challenges::find(session->settings().rules.id);
    if (!definition || !definition->nextBag)
        return -1;
    if (!view.gated || !rooms::viewReady() || (!session->isHost() && !view.authoritative))
        return -2;
    return compat::challenges::nextSeat(session->slot(), session->players());
}
unsigned difficulty() {
    return session ? session->settings().difficulty : 0;
}
bool startingPartyHasCharacter(int kind) {
    if (!session || view.gated || session->phase() != lan::Phase::running)
        return false;
    for (unsigned slot = 0; slot < session->players(); ++slot)
        if ((session->connectedMask() & (1u << slot)) &&
            session->settings().characters[slot] == kind)
            return true;
    return false;
}
bool ending() {
    return view.playingEnding;
}
std::uint32_t worldEpoch() {
    return view.floorEpoch;
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
    session->poll();
    const int top = lua.getTop(state);
    lua.rawGetI(state, registry, presentRef);
    lan::Writer packed(lan::Message::input);
    const auto preview = input::previewPhysicalInput();
    const input::MovementPreviewScope movementPreview(preview, localViewSlot() + 1);
    packed.input(preview);
    lua.pushLString(state, reinterpret_cast<const char*>(packed.bytes.data() + 1),
                    packed.bytes.size() - 1);
    // Movement displayed between network samples belongs to the upcoming
    // input, not the last sent sample (which the host may already acknowledge).
    lua.pushInteger(state, nextInputTick);
    if (call(presentRef, 2, 0, top))
        rooms::presentCamera();
}
void refreshAutomation(std::uint32_t renderFrame) {
    if (!state || !view.gated || !session || session->phase() != lan::Phase::running) {
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
    if (!view.gated || !session || session->phase() != lan::Phase::running)
        return;
    backend::hideConsole();
}
void beginStage(bool same, int animation, unsigned restart, unsigned cinematic) {
    if (!view.gated || !session || !session->isHost() || session->phase() != lan::Phase::running)
        return;
    auto value = backend::stage();
    ++view.floorEpoch;
    value.epoch = view.floorEpoch;
    value.same = same;
    value.animation = animation;
    value.restart = restart;
    if (restart) {
        value.level = 1;
        value.type = 0;
    }
    value.cinematic = cinematic;
    value.sourceRoom = rooms::floorSourceRoom();
    if (!session->beginStage(value)) {
        fail("Native floor transaction rejected");
        return;
    }
    view.playingCinematic = cinematic != 0;
    view.cinematicReady = false;
    if (view.playingCinematic) {
        input::reset();
        view.pendingHalf = false;
    }
    if (logger)
        logger("floor_event=SENT epoch=" + std::to_string(view.floorEpoch));
}
void prepareEnding() {
    view.playingEnding = true;
    input::reset();
    view.pendingHalf = false;
}
bool beginEnding(unsigned ending, bool completed) {
    if (!view.gated || !session || !session->isHost() || session->phase() != lan::Phase::running ||
        !session->beginEnding(ending, readProgress(), completed))
        return false;
    prepareEnding();
    if (logger)
        logger("ending_event=SENT id=" + std::to_string(ending) +
               " completed=" + std::to_string(completed));
    return true;
}
void beginRewind(std::span<const std::uint8_t> bytes) {
    if (!view.gated || !session || !session->isHost() || session->phase() != lan::Phase::running)
        return;
    auto value = backend::stage();
    value.epoch = ++view.floorEpoch;
    value.animation = 12;
    value.rewind.assign(bytes.begin(), bytes.end());
    session->beginStage(value);
    if (logger)
        logger("hourglass_event=SENT epoch=" + std::to_string(view.floorEpoch) +
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
    return view.gated && session ? static_cast<int>(session->slot()) : -1;
}
void requestWindowClose() {
    if (!view.gated || !session)
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
    if (view.gated)
        input::finishUpdate();
}
void halfCompleted() {
    if (!view.gated || !view.pendingHalf || view.playingEnding)
        return;
    view.pendingHalf = false;
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
    if (!lua.load(module, {isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField,
                           isaac::lua::Symbol::createTable, isaac::lua::Symbol::pushInteger,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::pushString,
                           isaac::lua::Symbol::pushLString, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::toString,
                           isaac::lua::Symbol::getTop,      isaac::lua::Symbol::getGlobal,
                           isaac::lua::Symbol::setTop,      isaac::lua::Symbol::pushValue,
                           isaac::lua::Symbol::type,        isaac::lua::Symbol::ref,
                           isaac::lua::Symbol::unref,       isaac::lua::Symbol::rawGetI,
                           isaac::lua::Symbol::rawSetI,     isaac::lua::Symbol::pcall,
                           isaac::lua::Symbol::toBoolean}))
        return false;
    auto function = [&](const char* name, LuaFunction fn) {
        lua.pushClosure(L, fn, 0);
        lua.setField(L, -2, name);
    };
    function("api_info", integrationInfo);
    function("api_send", integrationSend);
    function("api_receive", integrationReceive);
    function("chat_send", communicationSend);
    function("chat_receive", communicationReceive);
    function("chat_execute", executeChatCommand);
    function("net_host", host);
    function("net_join", join);
    function("net_poll", poll);
    function("net_phases", phaseValues);
    function("net_commands", commandValues);
    function("net_challenges", challengeList);
    function("net_characters", characterList);
    function("pause_menu_state", pauseMenuState);
    function("net_challenge", selectChallenge);
    function("net_finish_challenge", finishChallenge);
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
    function("net_retry_save", retrySavedArchive);
    function("net_command", sharedCommand);
    function("net_floor_epoch", epoch);
    return true;
}
} // namespace isaac::runtime

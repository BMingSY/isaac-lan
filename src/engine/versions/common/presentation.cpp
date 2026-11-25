#include "engine/lua_api.h"
#include "engine/versions/common/victory_prompt.h"
#include "engine/versions/common/presentation_bindings.h"
#include "engine/versions/common/player_hud.h"
#include "compat/game_ids.h"
#include "engine/presentation.h"
#include "engine/animation_skip.h"
#include "engine/frontend.h"
#include "engine/crafting_hud.h"
#include "engine/challenge_hud.h"
#include "engine/item_presentation.h"
#include "engine/rooms.h"
#include "core/intro_barrier.h"
#include "compat/bosses/encounters.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include <MinHook.h>
#include <deque>
#include <map>
#include <array>
#include <string>
#include <utility>

namespace native = isaac::engine::native_presentation;

namespace isaac::presentation {
namespace {
const auto& bindings = native::bindings;
std::uintptr_t image = 0;
bool installed = false;
constexpr unsigned maxIntroEvents = 32, introEventBytes = 32, introLifetime = 90;
constexpr int enterPhase = 2, exitPhase = 3;
constexpr unsigned specialIntro = 99, specialStage = 35, shopType = 1, specialShop = 1000;
constexpr unsigned clearedRoom = 1;
template <class T> T& at(std::uintptr_t p, unsigned offset) {
    return *reinterpret_cast<T*>(p + offset);
}
std::uintptr_t currentGame() {
    return image ? at<std::uintptr_t>(image, bindings.game) : 0;
}
struct Intro {
    unsigned serial, tick, audience;
    int stage, type, dimension, room;
    unsigned first, second;
};
std::deque<Intro> intros;
unsigned serial = 0;
std::map<IntroBarrier::Room, unsigned> seen;
unsigned played = 0;
unsigned hostIntro = 0;
using HasCollectible = bool(__attribute__((thiscall)) *)(void*, int, bool);
HasCollectible originalHasCollectible;
bool __attribute__((fastcall)) visibleCollectible(void* player, void*, int item, bool effects) {
    // Room::Render keeps the whole roster available to HUDs, but Night Light
    // walks it without checking whether the holder belongs to this room.
    const auto caller = reinterpret_cast<std::uintptr_t>(__builtin_return_address(0)) - image;
    if (item == compat::ids::collectible::nightLight &&
        caller == bindings.entry.nightLightQueryReturn && rooms::virtualized()) {
        const auto controller =
            at<int>(reinterpret_cast<std::uintptr_t>(player), bindings.layout.playerController);
        if (controller < 1 || controller > static_cast<int>(lan::maxPlayers) ||
            !(rooms::soundAudience() & (1u << (controller - 1))))
            return false;
    }
    return originalHasCollectible(player, item, effects);
}
IntroBarrier waiting;
bool simulatingIntro = false;
using StartIntro = void(__attribute__((thiscall)) *)(void*, unsigned, unsigned);
StartIntro originalIntro;
void finishIntro() {
    if (const auto game = currentGame())
        bindings.finishIntro(image, game + bindings.layout.game.transition);
}
void playIntro(void* transition, unsigned first, unsigned second) {
    const auto game = currentGame();
    if (!game)
        return;
    const auto target = reinterpret_cast<std::uintptr_t>(transition);
    // StartBossIntro consults the transition's destination descriptor while
    // loading native versus graphics. LAN already entered this room without
    // the global door transition, so supply its current native destination.
    at<int>(target, bindings.layout.transition.index) =
        at<int>(game, bindings.layout.game.roomIndex);
    at<int>(target, bindings.layout.transition.dimension) =
        at<int>(game, bindings.layout.game.dimension);
    bindings.prepareActor(image, game, target);
    originalIntro(transition, first, second);
}
void __attribute__((fastcall)) startIntro(void* transition, void*, unsigned first,
                                          unsigned second) {
    const auto audience = rooms::soundAudience();
    if (!audience) {
        originalIntro(transition, first, second);
        return;
    }
    // Replica room initialization can request a provisional intro. Its native
    // UI is started once from the authoritative event after that room arrives.
    if (runtime::replica())
        return;
    const auto game = currentGame();
    if (!game)
        return;
    const bool terminal =
        rooms::finalCombat() ||
        compat::bosses::gatherHomeCombat(at<int>(game, bindings.layout.game.stage),
                                         at<int>(game, bindings.layout.game.stageType),
                                         first == specialIntro, audience, rooms::connected());
    if (terminal && (audience & rooms::connected()) != rooms::connected()) {
        // Gather before the native versus screen. The complete roster then
        // shares its control lock and the encounter's cinematics.
        if (rooms::gatherForTransition([=] {
                rooms::withRoomPlayers(0, [&] { startIntro(transition, nullptr, first, second); });
            }))
            return;
    }
    intros.push_back({++serial, runtime::tick(), audience,
                      at<int>(game, bindings.layout.game.stage),
                      at<int>(game, bindings.layout.game.stageType),
                      at<int>(game, bindings.layout.game.dimension),
                      at<int>(game, bindings.layout.game.roomIndex), first, second});
    const auto& event = intros.back();
    waiting.start({event.stage, event.type, event.dimension, event.room}, event.serial, event.tick,
                  audience);
    while (intros.size() > maxIntroEvents)
        intros.pop_front();
    // A native intro owns the process-wide transition screen. Background room
    // entry must notify its occupants without taking over the host's viewport.
    if (audience & 1u) {
        hostIntro = event.serial;
        waiting.observe(0, hostIntro, true);
        played = event.serial;
        playIntro(transition, first, second);
    }
}
isaac::lua::API lua{};
int minimap(lua_State* L) {
    lua.createTable(L, 0, 2);
    if (runtime::localViewSlot() < 0)
        return 1;
    unsigned index = 0;
    for (const auto& view : frontend::minimapViews()) {
        lua.createTable(L, 0, 10);
        for (const auto& [key, value] : {std::pair{"x", view.x},
                                         {"y", view.y},
                                         {"cellWidth", view.cellWidth},
                                         {"cellHeight", view.cellHeight},
                                         {"left", view.clip.left},
                                         {"top", view.clip.top},
                                         {"right", view.clip.right},
                                         {"bottom", view.clip.bottom},
                                         {"alpha", view.alpha}}) {
            lua.pushNumber(L, value);
            lua.setField(L, -2, key);
        }
        lua.pushInteger(L, view.dimension);
        lua.setField(L, -2, "dimension");
        lua.setField(L, -2, std::to_string(index++).c_str());
    }
    return 1;
}
int playerHuds(lua_State* L) {
    namespace panels = engine::native_player_hud;
    lua.createTable(L, 0, panels::primaryPanels);
    const auto manager = at<std::uintptr_t>(image, bindings.manager);
    const auto game = currentGame();
    if (!manager || at<int>(manager, bindings.layout.managerScene) != 2 || !game ||
        runtime::localViewSlot() < 0)
        return 1;
    const auto width = at<float>(image, bindings.logicalWidth);
    const auto height = at<float>(image, bindings.logicalHeight);
    const int local = runtime::localViewSlot();
    const bool personal = local >= 0 && panels::localOnly(rooms::connected());
    rooms::withView(
        [&] {
            for (unsigned i = 0; i < panels::primaryPanels; ++i) {
                const auto anchor = bindings.hudAnchor(image, game, i, width, height);
                if (!anchor || (personal && anchor->slot != local))
                    continue;
                lua.createTable(L, 0, 3);
                lua.pushInteger(L, anchor->layout);
                lua.setField(L, -2, "layout");
                lua.pushNumber(L, anchor->x);
                lua.setField(L, -2, "x");
                lua.pushNumber(L, anchor->y);
                lua.setField(L, -2, "y");
                lua.setField(L, -2, std::to_string(anchor->slot).c_str());
            }
        },
        personal);
    return 1;
}
int events(lua_State* L) {
    try {
        if (lua.getTop(L) == 1 && !runtime::replica()) {
            const auto slot = lua.checkInteger(L, 1);
            lan::Writer w(lan::Message::world);
            if (slot >= 0 && slot < 4)
                for (const auto& e : intros) {
                    if (!(e.audience & (1u << slot)) ||
                        !waiting.pending(slot, e.serial, runtime::tick()))
                        continue;
                    for (auto v :
                         {e.serial, e.tick, static_cast<unsigned>(e.stage),
                          static_cast<unsigned>(e.type), static_cast<unsigned>(e.dimension),
                          static_cast<unsigned>(e.room), e.first, e.second})
                        w.u32(v);
                }
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        if (!runtime::replica())
            throw std::runtime_error("Only replicas apply presentation events");
        std::size_t size = 0;
        const auto bytes = lua.checkString(L, 1, &size);
        if (size % introEventBytes || size > maxIntroEvents * introEventBytes)
            throw std::runtime_error("Invalid intro events");
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        const auto game = currentGame();
        if (!game)
            throw std::runtime_error("Missing game for intro events");
        bool retained = false;
        for (std::size_t i = 0; i < size / introEventBytes; ++i) {
            const auto id = r.u32();
            r.u32(); // Event origin tick; delivery remains valid until acknowledged.
            const int stage = r.u32(), type = r.u32(), dimension = r.u32(), room = r.u32();
            const auto first = r.u32(), second = r.u32();
            retained |= id == played;
            const IntroBarrier::Room key{stage, type, dimension, room};
            const auto previous = seen.find(key);
            // A late arrival may join an older event after having watched a
            // newer one in another room. Deduplicate within its own room.
            if (previous != seen.end() && id <= previous->second)
                continue;
            rooms::withView(
                [&] {
                    if (stage != at<int>(game, bindings.layout.game.stage) ||
                        type != at<int>(game, bindings.layout.game.stageType) ||
                        dimension != at<int>(game, bindings.layout.game.dimension) ||
                        room != at<int>(game, bindings.layout.game.roomIndex))
                        return;
                    playIntro(reinterpret_cast<void*>(game + bindings.layout.game.transition),
                              first, second);
                    // A view can arrive before its room is ready. Only consume an
                    // event after playing it; the authority retries until completion.
                    seen[key] = played = id;
                    retained = true;
                },
                true);
        }
        r.finish();
        // The complete accepted view carries all still-pending intros. Once
        // the original audience finishes, its event disappears and a late
        // viewer completes the native screen instead of extending combat's wait.
        if (played && !retained && introActive())
            rooms::withView(finishIntro, true);
        lua.pushBoolean(L, true);
        return 1;
    } catch (const std::exception& e) {
        runtime::abort(e.what());
        lua.pushBoolean(L, false);
        return 1;
    }
}
int resetLua(lua_State*) {
    reset();
    return 0;
}
int active(lua_State* L) {
    lua.pushBoolean(L, introActive());
    return 1;
}
int victoryPrompt(lua_State* L) {
    const auto state = engine::native_victory_prompt::read();
    lua.pushBoolean(L, state.open);
    lua.pushInteger(L, state.selection);
    lua.pushInteger(L, state.result);
    lua.pushBoolean(L, state.nativeVote);
    lua.pushBoolean(L, state.idle);
    return 5;
}
} // namespace
IntroSimulationScope::IntroSimulationScope(bool advance) {
    if (simulatingIntro)
        return;
    simulatingIntro = entered = true;
    try {
        if (runtime::replica() || !hostIntro || !rooms::stateReady())
            return;
        const auto game = currentGame();
        if (!game)
            return;
        const auto target = game + bindings.layout.game.transition;
        if (at<int>(target, bindings.layout.transition.state) == 0) {
            observeIntro(0, hostIntro, false);
            hostIntro = 0;
            return;
        }
        if (at<int>(target, bindings.layout.transition.state) != 2 &&
            at<int>(target, bindings.layout.transition.state) != 3)
            return;
        if (!waiting.pending(0, hostIntro, runtime::tick())) {
            rooms::withRoomPlayers(0, finishIntro);
            observeIntro(0, hostIntro, false);
            hostIntro = 0;
            return;
        }
        if (advance && at<int>(game, bindings.layout.game.pauseMenu) == 0) {
            using Update = void(__attribute__((thiscall))*)(void*);
            // Game::Update otherwise advances this screen and returns before ANY
            // Room::Update. Advance it once, then let the room scheduler run.
            rooms::withRoomPlayers(0, [&] {
                reinterpret_cast<Update>(image + bindings.entry.updateTransition)(
                    reinterpret_cast<void*>(target));
            });
            waiting.observe(0, hostIntro, at<int>(target, bindings.layout.transition.state) != 0);
            if (at<int>(target, bindings.layout.transition.state) == 0)
                hostIntro = 0;
        }
        if (at<int>(target, bindings.layout.transition.state) == enterPhase ||
            at<int>(target, bindings.layout.transition.state) == exitPhase) {
            transition = target;
            saved = at<int>(target, bindings.layout.transition.state);
            at<int>(target, bindings.layout.transition.state) = 0;
        }
    } catch (...) {
        simulatingIntro = entered = false;
        throw;
    }
}
IntroSimulationScope::~IntroSimulationScope() {
    if (!entered)
        return;
    simulatingIntro = false;
    const auto game = currentGame();
    if (transition && game && game + bindings.layout.game.transition == transition &&
        at<int>(transition, bindings.layout.transition.state) == 0)
        at<int>(transition, bindings.layout.transition.state) = saved;
}
namespace {
// The two native presentation hooks own one transaction. Subcomponents keep
// their separate installation/ownership boundaries; startup aborts on failure.
bool installHooks(std::uintptr_t base) {
    if (!base || installed)
        return false;
    image = base;
    std::array<void*, 2> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned rva, auto detour, auto& original) {
        auto* target = reinterpret_cast<void*>(base + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(detour),
                          reinterpret_cast<void**>(&original)) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success =
        hook(bindings.entry.hasCollectible, visibleCollectible, originalHasCollectible) &&
        hook(bindings.entry.startIntro, startIntro, originalIntro);
    if (success) {
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
        if (success)
            success = MH_ApplyQueued() == MH_OK;
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        originalHasCollectible = nullptr;
        originalIntro = nullptr;
        image = 0;
    }
    installed = success;
    return success;
}
} // namespace
bool install(std::uintptr_t base) {
    return base && !installed && animation::install(base) && installCraftingHud(base) &&
           installChallengeHud(base) && items::install(base) &&
           engine::native_victory_prompt::install(base) && installHooks(base);
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {isaac::lua::Symbol::getTop, isaac::lua::Symbol::checkInteger,
                           isaac::lua::Symbol::checkString, isaac::lua::Symbol::pushLString,
                           isaac::lua::Symbol::pushBoolean, isaac::lua::Symbol::pushInteger,
                           isaac::lua::Symbol::pushNumber, isaac::lua::Symbol::createTable,
                           isaac::lua::Symbol::pushClosure, isaac::lua::Symbol::setField}))
        return false;
    lua.pushClosure(L, events, 0);
    lua.setField(L, -2, "presentation_events");
    lua.pushClosure(L, resetLua, 0);
    lua.setField(L, -2, "presentation_reset");
    lua.pushClosure(L, active, 0);
    lua.setField(L, -2, "presentation_active");
    lua.pushClosure(L, playerHuds, 0);
    lua.setField(L, -2, "presentation_player_huds");
    lua.pushClosure(L, minimap, 0);
    lua.setField(L, -2, "presentation_minimap");
    lua.pushClosure(L, victoryPrompt, 0);
    lua.setField(L, -2, "victory_lap_prompt");
    return animation::bind(L, module) && items::bind(L, module);
}
void reset() {
    animation::reset();
    items::reset();
    intros.clear();
    waiting.clear();
    seen.clear();
    serial = played = hostIntro = 0;
}
unsigned playedIntro() {
    return played;
}
bool introActive() {
    const auto game = currentGame();
    if (!game)
        return false;
    const auto transition = game + bindings.layout.game.transition;
    const auto mode = at<int>(transition, bindings.layout.transition.state);
    return (mode == enterPhase || mode == exitPhase) && bindings.introMarker(transition);
}
std::vector<std::pair<unsigned, unsigned>> introAudiences() {
    std::vector<std::pair<unsigned, unsigned>> result;
    if (runtime::replica())
        return result;
    for (const auto& event : intros)
        if (const auto audience =
                waiting.audience(event.serial, runtime::tick(), rooms::connected()))
            result.emplace_back(event.serial, audience);
    return result;
}
bool skipIntro(unsigned id) {
    if (runtime::replica()) {
        if (played != id || !introActive())
            return false;
        rooms::withView(finishIntro, true);
        return true;
    }
    const auto audience = waiting.audience(id, runtime::tick(), rooms::connected());
    if (!audience)
        return false;
    waiting.finish(id);
    if (hostIntro == id) {
        if (introActive())
            rooms::withRoomPlayers(0, finishIntro);
        observeIntro(0, id, false);
        hostIntro = 0;
    }
    return true;
}
void observeIntro(unsigned slot, unsigned id, bool active) {
    const auto completed = waiting.observe(slot, id, active);
    if (!completed || runtime::ending())
        return;
    // A guest-only versus screen never runs on the authority. Complete its
    // native control restoration once, after that guest finished both phases,
    // using only its actors in the room where the event originated.
    rooms::withPlayer(slot, [&] {
        const auto game = currentGame();
        if (!game)
            return;
        const std::array room{at<int>(game, bindings.layout.game.stage),
                              at<int>(game, bindings.layout.game.stageType),
                              at<int>(game, bindings.layout.game.dimension),
                              at<int>(game, bindings.layout.game.roomIndex)};
        if (room != *completed || !bindings.canRestoreControls(game))
            return;
        using Controls = void(__attribute__((thiscall))*)(void*, bool);
        reinterpret_cast<Controls>(image + bindings.entry.setControls)(
            reinterpret_cast<void*>(game + bindings.layout.game.playerManager), true);
    });
}
bool roomPaused() {
    const auto game = currentGame();
    if (!game)
        return false;
    const std::array key{at<int>(game, bindings.layout.game.stage),
                         at<int>(game, bindings.layout.game.stageType),
                         at<int>(game, bindings.layout.game.dimension),
                         at<int>(game, bindings.layout.game.roomIndex)};
    // A missing acknowledgement must not leave a room frozen after a player
    // disconnects or fails to render. Normal completion is event-specific.
    return waiting.paused(key, runtime::tick(), rooms::connected() & rooms::soundAudience());
}
void roomEntered(std::uintptr_t room, bool created) {
    if (runtime::replica() || !room || !currentGame())
        return;
    if (!created) {
        const auto game = currentGame();
        const IntroBarrier::Room key{at<int>(game, bindings.layout.game.stage),
                                     at<int>(game, bindings.layout.game.stageType),
                                     at<int>(game, bindings.layout.game.dimension),
                                     at<int>(game, bindings.layout.game.roomIndex)};
        for (auto& event : intros) {
            if (IntroBarrier::Room{event.stage, event.type, event.dimension, event.room} != key)
                continue;
            // Joining a resident room skips native Init. Subscribe its new
            // occupants to the existing screen without restarting anyone who
            // has already played it or extending the original timeout.
            const auto added = waiting.join(key, event.serial, runtime::tick(),
                                            rooms::soundAudience() & rooms::connected());
            event.audience |= added;
            if (added & 1u) {
                hostIntro = played = event.serial;
                waiting.observe(0, hostIntro, true);
                playIntro(reinterpret_cast<void*>(game + bindings.layout.game.transition),
                          event.first, event.second);
            }
        }
        return;
    }
    // These are the same native boss IDs and living-enemy checks used by
    // RoomTransition::ChangeRoom. Per-player room entry skips that global
    // transition, but must retain its original versus presentation.
    const auto first = at<unsigned>(room, bindings.layout.room.firstBoss),
               second = at<unsigned>(room, bindings.layout.room.secondBoss);
    if (first && at<int>(room, bindings.layout.room.enemies) +
                         at<int>(room, bindings.layout.room.delayedEnemies) >
                     0) {
        const auto game = currentGame();
        startIntro(reinterpret_cast<void*>(game + bindings.layout.game.transition), nullptr, first,
                   second);
    } else {
        const auto descriptor = at<std::uintptr_t>(room, bindings.layout.room.descriptor);
        const auto data =
            descriptor ? at<std::uintptr_t>(descriptor, bindings.layout.descriptor.data) : 0;
        // The native special-room entry also starts a versus screen before
        // the room's boss-ID cache has been populated.
        if (data && at<int>(data, bindings.layout.config.stage) == specialStage &&
            at<int>(data, bindings.layout.config.type) == shopType &&
            at<int>(data, bindings.layout.config.variant) == specialShop &&
            !(at<unsigned>(descriptor, bindings.layout.descriptor.flags) & clearedRoom)) {
            const auto game = currentGame();
            startIntro(reinterpret_cast<void*>(game + bindings.layout.game.transition), nullptr,
                       specialIntro, 0);
        }
    }
}
} // namespace isaac::presentation

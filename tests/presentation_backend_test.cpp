#include "test_support.h"
#include "engine/versions/common/presentation.cpp"
#include <algorithm>
#include <cstring>
#include <map>
#include <vector>
#ifdef ISAAC_LAN_TEST_REPENTANCE
#include "engine/versions/repentance/entrypoints.h"
namespace backend = isaac::engine::repentance;
constexpr unsigned transitionOffset = 0x1b6c0, playersOffset = 0x1ba50, managerOffset = 0x1ba40;
constexpr unsigned roomIndexOffset = 0x18194, dimensionOffset = 0x1819c, pauseOffset = 0x10203c;
constexpr unsigned firstBossOffset = 0x1d1c, secondBossOffset = 0x1d20;
constexpr unsigned controllerOffset = 0x154c, controlsOffset = 0x360, markerOffset = 0x348;
constexpr unsigned hudOffset = 0x3da4c, hudVisibleOffset = 0xc3eb6, hudStride = 0x6b0;
#else
#include "engine/versions/repentance_plus/entrypoints.h"
namespace backend = isaac::engine::repentance_plus;
constexpr unsigned transitionOffset = 0x1b83c, playersOffset = 0x1baa8, managerOffset = 0x1baa8;
constexpr unsigned roomIndexOffset = 0x18304, dimensionOffset = 0x1830c, pauseOffset = 0x23a7c;
constexpr unsigned firstBossOffset = 0x1bb0, secondBossOffset = 0x1bb4;
constexpr unsigned controllerOffset = 0x161c, controlsOffset = 0x410, markerOffset = 0x238;
constexpr unsigned hudOffset = 0x1da04, hudVisibleOffset = 0x54cc, hudStride = 0x6dc;
#endif
struct lua_State {
    struct Table {
        std::map<std::string, double> values;
        std::map<std::string, Table> children;
    };
    int top = 1;
    long long integer = 0;
    std::string input, output;
    bool success = false;
    std::vector<Table> tables;
    std::optional<double> value;
};
namespace {
namespace presentation = isaac::presentation;
using Address = std::uintptr_t;
using Start = void(__attribute__((thiscall)) *)(void*, unsigned, unsigned);
using Has = bool(__attribute__((thiscall)) *)(void*, int, bool);
unsigned char* image;
std::vector<unsigned char> game(0x290000), room(0x2000);
std::vector<unsigned char> manager(0x2b000);
std::array<std::array<unsigned char, 0x1700>, 4> players{};
std::array<Address, 4> roster{};
std::array<int, 4> playerRooms{10, 20, 10, 20};
unsigned tick = 100, audience = 1, connected = 3;
int localSlot = 0;
bool replica = false, ending = false, ready = true, virtualized = true, finalCombat = false;
bool gatherAccepted = true, failSelector = false;
unsigned starts = 0, updates = 0, restores = 0, queries = 0, assignments = 0, itemResets = 0;
unsigned observedFirst = 0, observedSecond = 0, observedRoster = 0;
int observedIndex = 0, observedDimension = 0, observedItem = 0;
bool observedEffects = false, localOnly = false;
void* observedActor = nullptr;
void* observedPlayer = nullptr;
std::string lastError;
std::function<void()> gathered;
std::map<Address, std::vector<Address*>> registered;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void* transition() {
    return game.data() + transitionOffset;
}
void setRoster(unsigned mask) {
    unsigned count = 0;
    for (unsigned slot = 0; slot < players.size(); ++slot)
        if (mask & (1u << slot))
            roster[count++] = reinterpret_cast<Address>(players[slot].data());
    field<Address>(game.data(), playersOffset) = reinterpret_cast<Address>(roster.data());
    field<Address>(game.data(), playersOffset + 4) =
        reinterpret_cast<Address>(roster.data() + count);
}
unsigned currentRoster() {
    unsigned mask = 0;
    for (auto p = field<Address>(game.data(), playersOffset);
         p != field<Address>(game.data(), playersOffset + 4); p += 4) {
        auto* actor = reinterpret_cast<void*>(field<Address>(reinterpret_cast<void*>(p), 0));
        mask |= 1u << (field<int>(actor, controllerOffset) - 1);
    }
    return mask;
}
void withRoster(unsigned mask, const std::function<void()>& action) {
    const auto previous = currentRoster();
    setRoster(mask);
    try {
        action();
    } catch (...) {
        setRoster(previous);
        throw;
    }
    setRoster(previous);
}
void __attribute__((fastcall)) nativeStart(void* object, void*, unsigned first, unsigned second) {
    require(object == transition(), "Intro receiver is not the native transition");
    ++starts;
    observedFirst = first;
    observedSecond = second;
    observedIndex = field<int>(object, 0x14);
    observedDimension = field<int>(object, 0x18);
    observedRoster = currentRoster();
#ifdef ISAAC_LAN_TEST_REPENTANCE
    observedActor = reinterpret_cast<void*>(field<Address>(object, 0x340));
    field<bool>(object, markerOffset) = true;
#else
    observedActor = reinterpret_cast<void*>(field<Address>(game.data(), 0x1bb74));
    field<unsigned>(object, markerOffset) = first;
#endif
    field<int>(object, 0) = 2;
}
void __attribute__((fastcall)) nativeUpdate(void* object, void*) {
    require(object == transition(), "Transition update receiver changed");
    ++updates;
    observedRoster = currentRoster();
    const auto state = field<int>(object, 0);
    field<int>(object, 0) = state == 2 ? 3 : 0;
}
void __attribute__((fastcall)) nativeControls(void* object, void*, bool enabled) {
    require(object == game.data() + managerOffset && enabled,
            "Control restoration used the wrong manager or argument");
    ++restores;
    observedRoster = currentRoster();
    for (unsigned slot = 0; slot < players.size(); ++slot)
        if (observedRoster & (1u << slot))
            field<bool>(players[slot].data(), controlsOffset) = true;
}
bool __attribute__((fastcall)) nativeHas(void* object, void*, int item, bool effects) {
    ++queries;
    observedPlayer = object;
    observedItem = item;
    observedEffects = effects;
    return true;
}
void __attribute__((fastcall)) nativeAssign(void* reference, void* actor) {
    require(reference == static_cast<unsigned char*>(transition()) + 0x340,
            "Intro assigned an unrelated EntityPtr");
    auto* slot = static_cast<Address*>(reference);
    auto& old = registered[*slot];
    old.erase(std::remove(old.begin(), old.end(), slot), old.end());
    *slot = reinterpret_cast<Address>(actor);
    if (actor)
        registered[*slot].push_back(slot);
    ++assignments;
}
#ifndef ISAAC_LAN_TEST_REPENTANCE
int __attribute__((fastcall)) nativeHudLayout(void* hud, void*, int index, void* player) {
    require(hud == game.data() + hudOffset && index >= 0 && index < 4 &&
                reinterpret_cast<Address>(player) == field<Address>(hud, index * hudStride),
            "HUD layout query changed the native receiver or player");
    return index;
}
float* __attribute__((fastcall)) nativeHudPosition(void* hud, void*, float* point, int index,
                                                   int layout) {
    require(hud == game.data() + hudOffset && layout == index,
            "HUD position query changed the receiver or layout");
    point[0] = 100 + index * 10;
    point[1] = 50 + index * 5;
    return point;
}
#endif
void jump(unsigned char* target, void* function) {
    std::memset(target, 0x90, 16);
    target[0] = 0xe9;
    const auto relative =
        reinterpret_cast<Address>(function) - reinterpret_cast<Address>(target + 5);
    std::memcpy(target + 1, &relative, sizeof(relative));
}
void start(unsigned first = 10, unsigned second = 20) {
    reinterpret_cast<Start>(image + backend::entry::roomTransitionStartBossIntro)(transition(),
                                                                                  first, second);
}
std::string collect(int slot) {
    lua_State state;
    state.integer = slot;
    require(presentation::events(&state) == 1, "Intro collection returned the wrong Lua arity");
    return state.output;
}
bool apply(const std::string& bytes) {
    lua_State state;
    state.input = bytes;
    require(presentation::events(&state) == 1, "Intro application returned the wrong Lua arity");
    return state.success;
}
std::string event(unsigned id, unsigned time, int stage, int type, int dimension, int index,
                  unsigned first = 10, unsigned second = 20) {
    std::string bytes;
    for (unsigned word :
         {id, time, static_cast<unsigned>(stage), static_cast<unsigned>(type),
          static_cast<unsigned>(dimension), static_cast<unsigned>(index), first, second})
        for (int shift = 24; shift >= 0; shift -= 8)
            bytes.push_back(static_cast<char>(word >> shift));
    return bytes;
}
void reset() {
    presentation::reset();
    std::fill(game.begin(), game.end(), 0);
    std::fill(room.begin(), room.end(), 0);
    for (unsigned slot = 0; slot < players.size(); ++slot) {
        players[slot].fill(0xa5);
        field<int>(players[slot].data(), controllerOffset) = slot + 1;
        field<bool>(players[slot].data(), controlsOffset) = false;
    }
    registered.clear();
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<int>(game.data(), 0) = 4;
    field<int>(game.data(), 4) = 1;
    field<int>(game.data(), roomIndexOffset) = 10;
    field<int>(game.data(), dimensionOffset) = 0;
    playerRooms = {10, 20, 10, 20};
    audience = 1;
    connected = 3;
    tick = 100;
    localSlot = 0;
    replica = ending = finalCombat = failSelector = false;
    ready = virtualized = gatherAccepted = true;
    gathered = {};
    starts = updates = restores = queries = assignments = 0;
    lastError.clear();
    setRoster(15);
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
bool ending() {
    return ::ending;
}
unsigned tick() {
    return ::tick;
}
int localViewSlot() {
    return localSlot;
}
void abort(const std::string& reason) {
    lastError = reason;
}
} // namespace isaac::runtime
namespace isaac::rooms {
unsigned soundAudience() {
    return audience;
}
unsigned connected() {
    return ::connected;
}
bool finalCombat() {
    return ::finalCombat;
}
bool virtualized() {
    return ::virtualized;
}
bool stateReady() {
    return ready;
}
bool gatherForTransition(const std::function<void()>& action) {
    if (gatherAccepted)
        gathered = action;
    return gatherAccepted;
}
bool withPlayer(unsigned slot, const std::function<void()>& action) {
    if (slot >= players.size() || failSelector)
        return false;
    const auto oldRoom = field<int>(game.data(), roomIndexOffset);
    field<int>(game.data(), roomIndexOffset) = playerRooms[slot];
    withRoster(1u << slot, action);
    field<int>(game.data(), roomIndexOffset) = oldRoom;
    return true;
}
bool withRoomPlayers(unsigned slot, const std::function<void()>& action) {
    if (failSelector)
        return false;
    unsigned mask = 0;
    for (unsigned i = 0; i < players.size(); ++i)
        if ((::connected & (1u << i)) && playerRooms[i] == playerRooms[slot])
            mask |= 1u << i;
    withRoster(mask, action);
    return true;
}
void withView(const std::function<void()>& action, bool localPlayersOnly) {
    localOnly = localPlayersOnly;
    withRoster(localPlayersOnly ? 1u << localSlot : ::connected, action);
}
} // namespace isaac::rooms
namespace isaac::presentation {
bool installCraftingHud(std::uintptr_t) {
    return true;
}
bool installChallengeHud(std::uintptr_t) {
    return true;
}
namespace items {
bool install(std::uintptr_t) {
    return true;
}
bool bind(lua_State*, HMODULE) {
    return true;
}
void reset(bool) {
    ++itemResets;
}
} // namespace items
} // namespace isaac::presentation
namespace isaac::engine::native_victory_prompt {
bool install(std::uintptr_t) {
    return true;
}
State read() {
    return {};
}
} // namespace isaac::engine::native_victory_prompt
namespace isaac::frontend {
const std::vector<presentation::MinimapView>& minimapViews() {
    static const std::vector<presentation::MinimapView> empty;
    return empty;
}
} // namespace isaac::frontend
int main() {
    try {
        require(!presentation::installHooks(0) && !presentation::introActive(),
                "Presentation accepted a missing native image");
        constexpr unsigned imageSize = 0x900000;
        image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate presentation fixture");
        auto* intro = image + backend::entry::roomTransitionStartBossIntro;
        auto* has = image + backend::entry::playerHasCollectible;
        jump(intro, reinterpret_cast<void*>(nativeStart));
        jump(has, reinterpret_cast<void*>(nativeHas));
        jump(image + backend::entry::roomTransitionUpdate, reinterpret_cast<void*>(nativeUpdate));
        jump(image + backend::entry::playerManagerSetControlsEnabled,
             reinterpret_cast<void*>(nativeControls));
        jump(image + backend::entry::entityPtrAssign, reinterpret_cast<void*>(nativeAssign));
#ifndef ISAAC_LAN_TEST_REPENTANCE
        jump(image + backend::entry::hUDPlayerLayout, reinterpret_cast<void*>(nativeHudLayout));
        jump(image + backend::entry::hUDPlayerPosition, reinterpret_cast<void*>(nativeHudPosition));
#endif
        auto* query = image + backend::entry::roomNightLightQuery;
        const unsigned char pushArguments[]{0xff, 0x74, 0x24, 0x08, 0xff, 0x74, 0x24, 0x08};
        std::memcpy(query - sizeof(pushArguments), pushArguments, sizeof(pushArguments));
        query[0] = 0xe8;
        const auto relative = reinterpret_cast<Address>(has) - reinterpret_cast<Address>(query + 5);
        std::memcpy(query + 1, &relative, 4);
        const unsigned char returnArguments[]{0xc2, 0x08, 0};
        std::memcpy(query + 5, returnArguments, sizeof(returnArguments));
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        const auto base = reinterpret_cast<Address>(image);
        for (auto* conflict : {intro, has}) {
            require(MH_CreateHook(conflict, reinterpret_cast<void*>(nativeStart), nullptr) == MH_OK,
                    "Prepare presentation hook conflict");
            require(!presentation::installHooks(base) && !presentation::image &&
                        !presentation::originalIntro && !presentation::originalHasCollectible,
                    "Failed presentation hooks retained partial state");
            require(MH_CreateHook(conflict, reinterpret_cast<void*>(nativeStart), nullptr) ==
                        MH_ERROR_ALREADY_CREATED,
                    "Presentation rollback removed a foreign hook");
            auto* other = conflict == intro ? has : intro;
            require(MH_CreateHook(other, reinterpret_cast<void*>(nativeStart), nullptr) == MH_OK,
                    "Presentation rollback leaked its hook");
            require(MH_RemoveHook(other) == MH_OK && MH_RemoveHook(conflict) == MH_OK,
                    "Clear presentation conflict");
        }
        require(presentation::install(base) && !presentation::install(base),
                "Presentation retry or duplicate-install handling failed");
        presentation::lua.getTop = [](lua_State* L) { return L->top; };
        presentation::lua.checkInteger = [](lua_State* L, int) { return L->integer; };
        presentation::lua.checkString = [](lua_State* L, int, std::size_t* size) {
            *size = L->input.size();
            return L->input.c_str();
        };
        presentation::lua.pushLString = [](lua_State* L, const char* data, std::size_t size) {
            L->output.assign(data, size);
            return L->output.c_str();
        };
        presentation::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
        presentation::lua.createTable = [](lua_State* L, int, int) { L->tables.emplace_back(); };
        presentation::lua.pushInteger = [](lua_State* L, long long value) { L->value = value; };
        presentation::lua.pushNumber = [](lua_State* L, double value) { L->value = value; };
        presentation::lua.setField = [](lua_State* L, int, const char* key) {
            if (L->value) {
                L->tables.back().values[key] = *L->value;
                L->value.reset();
            } else {
                auto child = std::move(L->tables.back());
                L->tables.pop_back();
                L->tables.back().children[key] = std::move(child);
            }
        };

        reset();
        audience = 0;
        field<int>(transition(), 0x14) = 77;
        start(30, 31);
        require(starts == 1 && observedFirst == 30 && observedSecond == 31 && observedIndex == 77 &&
                    collect(0).empty() && !presentation::playedIntro() && !assignments,
                "Ordinary native intro was adapted or published");
        reset();
        replica = true;
        start();
        require(!starts && !presentation::playedIntro(),
                "Replica replayed a provisional native intro");

        reset();
        audience = 2;
        field<int>(game.data(), roomIndexOffset) = 20;
        start();
        require(!starts && !presentation::playedIntro() && collect(0).empty() &&
                    collect(1) == event(1, 100, 4, 1, 0, 20) && presentation::roomPaused(),
                "A background intro took over the viewport or changed its event bytes");
        presentation::observeIntro(1, 1, true);
        presentation::observeIntro(1, 99, false);
        require(!restores && presentation::roomPaused(),
                "An unrelated acknowledgement unlocked a room");
        presentation::observeIntro(1, 1, false);
        require(restores == 1 && observedRoster == 2 && currentRoster() == 15 &&
                    field<bool>(players[1].data(), controlsOffset) &&
                    !field<bool>(players[0].data(), controlsOffset) && !presentation::roomPaused(),
                "Intro completion restored the wrong players or retained its room barrier");
        presentation::observeIntro(1, 1, false);
        require(restores == 1, "Duplicate intro completion restored controls again");
        for (int boundary : {0, 1, 2, 3, 4}) {
            reset();
            audience = 2;
            field<int>(game.data(), roomIndexOffset) = 20;
            start();
            if (boundary == 0)
                playerRooms[1] = 30;
            else if (boundary == 1)
                field<int>(game.data(), 0) = 5;
            else if (boundary == 2)
                field<int>(game.data(), dimensionOffset) = 1;
            else if (boundary == 3)
                ending = true;
            else
                failSelector = true;
            presentation::observeIntro(1, 1, false);
            require(!restores,
                    "Intro completion crossed a room, floor, ending or missing-player boundary");
        }
#ifndef ISAAC_LAN_TEST_REPENTANCE
        reset();
        audience = 2;
        field<int>(game.data(), roomIndexOffset) = 20;
        start();
        field<int>(game.data(), 0x26628) = 2;
        presentation::observeIntro(1, 1, false);
        require(!restores, "Repentance+ control restoration bypassed its native guard");
#endif
        reset();
        audience = 3;
        playerRooms[1] = 10;
        isaac::rooms::withRoomPlayers(0, [] { start(256, 20); });
        require(starts == 1 && observedIndex == 10 && observedDimension == 0 &&
                    observedRoster == 3 && observedActor == players[0].data() &&
                    presentation::introActive(),
                "Host intro lost its destination, actor, roster or full-width marker");
#ifdef ISAAC_LAN_TEST_REPENTANCE
        require(assignments == 1 &&
                    registered[reinterpret_cast<Address>(players[0].data())].size() == 1,
                "Repentance intro bypassed native EntityPtr registration");
        field<bool>(transition(), markerOffset) = false;
        field<unsigned char>(transition(), markerOffset + 1) = 0xff;
        require(!presentation::introActive(),
                "Repentance intro marker read adjacent flags as a boss ID");
        field<bool>(transition(), markerOffset) = true;
#endif
        {
            presentation::IntroSimulationScope outer(true);
            require(updates == 1 && field<int>(transition(), 0) == 0 && observedRoster == 3,
                    "Host intro failed to advance once before independent room simulation");
            {
                presentation::IntroSimulationScope nested(true);
                require(updates == 1, "Nested simulation advanced the intro twice");
            }
            require(field<int>(transition(), 0) == 0,
                    "Nested scope restored the outer transition early");
        }
        require(field<int>(transition(), 0) == 3, "Simulation did not restore the exit phase");
        field<int>(game.data(), pauseOffset) = 1;
        struct ScopeFailure {};
        try {
            presentation::IntroSimulationScope scope(true);
            require(updates == 1 && field<int>(transition(), 0) == 0,
                    "Paused simulation advanced the native intro");
            throw ScopeFailure{};
        } catch (const ScopeFailure&) {
        }
        require(field<int>(transition(), 0) == 3, "Exception lost the native intro phase");
        field<int>(game.data(), pauseOffset) = 0;
        { presentation::IntroSimulationScope scope(true); }
        require(updates == 2 && !presentation::introActive() && presentation::roomPaused(),
                "Host completion lost a guest's unfinished barrier");
        presentation::observeIntro(1, 1, false);
        require(!presentation::roomPaused(), "Guest completion did not release the shared room");
        reset();
        start();
        {
            presentation::IntroSimulationScope scope;
            field<int>(transition(), 0) = 4;
        }
        require(field<int>(transition(), 0) == 4, "Scope overwrote a newer native transition");
        start();
        {
            presentation::IntroSimulationScope scope;
            field<Address>(image, backend::globals::game) = 0;
        }
        require(!field<int>(transition(), 0), "Scope wrote into a released Game object");

        for (bool home : {false, true}) {
            reset();
            audience = 2;
            finalCombat = !home;
            if (home) {
                field<int>(game.data(), 0) = 13;
                field<int>(game.data(), 4) = 1;
            }
            start(home ? 99 : 10, 0);
            require(gathered && !starts && collect(1).empty(),
                    "Terminal intro began before gathering the connected party");
            audience = 3;
            playerRooms[1] = 10;
            auto resume = std::move(gathered);
            resume();
            require(starts == 1 && observedRoster == 3 && !collect(1).empty(),
                    "Gathered terminal intro did not resume in the shared roster");
        }
        reset();
        field<unsigned>(room.data(), firstBossOffset) = 41;
        field<unsigned>(room.data(), secondBossOffset) = 42;
        field<int>(room.data(), 0x12cc) = 1;
        presentation::roomEntered(reinterpret_cast<Address>(room.data()), true);
        require(starts == 1 && observedFirst == 41 && observedSecond == 42,
                "Room entry did not use the version's boss cache and delayed enemy count");
        field<int>(room.data(), 0x12cc) = 0;
        presentation::roomEntered(reinterpret_cast<Address>(room.data()), true);
        require(starts == 1, "Cleared room replayed its cached boss intro");
        std::array<unsigned char, 0x60> descriptor{}, config{};
        field<Address>(room.data(), 4) = reinterpret_cast<Address>(descriptor.data());
        field<Address>(descriptor.data(), 0x10) = reinterpret_cast<Address>(config.data());
        field<int>(config.data(), 0) = 35;
        field<int>(config.data(), 8) = 1;
        field<int>(config.data(), 12) = 1000;
        presentation::roomEntered(reinterpret_cast<Address>(room.data()), true);
        require(starts == 2 && observedFirst == 99 && !observedSecond,
                "Native special-room entry lost its provisional versus screen");
        field<unsigned>(descriptor.data(), 0x44) = 1;
        presentation::roomEntered(reinterpret_cast<Address>(room.data()), true);
        require(starts == 2, "Completed special room replayed its versus screen");

        reset();
        audience = 2;
        field<int>(game.data(), roomIndexOffset) = -3;
        field<int>(game.data(), dimensionOffset) = 2;
        for (unsigned i = 1; i <= 40; ++i) {
            field<int>(game.data(), roomIndexOffset) = i == 9 ? -3 : static_cast<int>(i);
            start(i, i + 1);
        }
        const auto queue = collect(1);
        require(queue.size() == 32 * 32 &&
                    queue.substr(0, 32) == event(9, 100, 4, 1, 2, -3, 9, 10) &&
                    queue.substr(31 * 32) == event(40, 100, 4, 1, 2, 40, 40, 41),
                "Bounded intro queue changed serialization, signed fields or event order");
        tick = 700;
        require(collect(1) == queue && collect(-1).empty() && collect(4).empty(),
                "Intro age or audience boundary changed");
        tick = 701;
        require(collect(1).empty(), "Expired intro event remained publishable");
        require(!presentation::roomPaused(),
                "Missing acknowledgement left the room paused forever");
        reset();
        audience = 2;
        start();
        connected = 1;
        require(!presentation::roomPaused(), "Disconnected guest retained a room barrier");

        reset();
        replica = true;
        localSlot = 1;
        require(apply(event(1, 100, 4, 1, 0, 10)) && starts == 1 && localOnly &&
                    observedActor == players[1].data() && observedRoster == 2 &&
                    currentRoster() == 15,
                "Replica intro did not replay in its borrowed local roster");
        require(apply(event(1, 100, 4, 1, 0, 10)) && starts == 1,
                "Replica replayed a duplicate event");
        require(apply(event(2, 9, 4, 1, 0, 10)) && starts == 2,
                "Unacknowledged intro expired before its authority withdrew it");
        for (const auto& bytes : {event(3, 100, 5, 1, 0, 10), event(4, 100, 4, 0, 0, 10),
                                  event(5, 100, 4, 1, 1, 10), event(6, 100, 4, 1, 0, 20)})
            require(apply(bytes) && starts == 2, "Replica played a foreign-room intro");
        require(apply(event(7, 101, 4, 1, 0, 10, 7, 8)) && starts == 3 &&
                    presentation::playedIntro() == 7 && observedFirst == 7 && observedSecond == 8,
                "Replica rejected a current event after discarding stale events");
        require(!apply(std::string(31, '\0')) && !lastError.empty() && starts == 3,
                "Truncated intro bytes were accepted or replayed");
        require(!apply(std::string(33 * 32, '\0')) && starts == 3,
                "Oversized intro batch was accepted or partially replayed");
#ifdef ISAAC_LAN_TEST_REPENTANCE
        auto* actor = players[1].data();
        for (auto* reference : registered[reinterpret_cast<Address>(actor)])
            *reference = 0;
        require(!field<Address>(transition(), 0x340),
                "Destroying the actor did not clear the registered transition reference");
#endif
        field<Address>(image, backend::globals::game) = 0;
        require(!presentation::introActive() && !presentation::roomPaused() &&
                    !apply(event(8, 100, 4, 1, 0, 10)),
                "Missing Game retained an intro view or accepted replay");

        reset();
        const auto roomQuery = reinterpret_cast<Has>(query - sizeof(pushArguments));
        for (int controller : {0, 1, 2, 3, 4, 5}) {
            field<int>(players[0].data(), controllerOffset) = controller;
            audience = 5;
            queries = 0;
            const bool expected = controller == 1 || controller == 3;
            require(roomQuery(players[0].data(), 425, false) == expected &&
                        queries == static_cast<unsigned>(expected),
                    "Night Light query included an absent or invalid room participant");
            require(reinterpret_cast<Has>(has)(players[0].data(), 425, true) &&
                        observedPlayer == players[0].data() && observedEffects &&
                        observedItem == 425,
                    "Night Light filtering escaped its Room::Render call site");
        }
        require(roomQuery(players[0].data(), 1, false) && observedItem == 1 && !observedEffects,
                "Room rendering changed another collectible query");
        virtualized = false;
        require(roomQuery(players[0].data(), 425, false),
                "Single-player rendering lost its original Night Light query");
        reset();
        field<Address>(image, backend::globals::manager) =
            reinterpret_cast<Address>(manager.data());
        field<int>(manager.data(), 8) = 2;
        field<float>(image, backend::globals::logicalWidth) = 480;
        field<float>(image, backend::globals::logicalHeight) = 270;
        auto* hud = game.data() + hudOffset;
        field<bool>(hud, hudVisibleOffset) = true;
        field<Address>(hud, 0) = reinterpret_cast<Address>(players[1].data());
        field<Address>(hud, hudStride) = reinterpret_cast<Address>(players[0].data());
        const auto beforeHud = game;
        lua_State hudState;
        require(presentation::playerHuds(&hudState) == 1 && hudState.tables.size() == 1 &&
                    hudState.tables[0].children.size() == 2 && game == beforeHud,
                "HUD bridge changed native objects or lost active player anchors");
        const auto& first = hudState.tables[0].children.at("1").values;
        const auto& second = hudState.tables[0].children.at("0").values;
#ifdef ISAAC_LAN_TEST_REPENTANCE
        require(first.at("layout") == 0 && first.at("x") == 48 && first.at("y") == 12 &&
                    second.at("layout") == 1 && second.at("x") == 369 && second.at("y") == 12,
                "Repentance HUD binding changed corner coordinates or controller identity");
#else
        require(first.at("layout") == 0 && first.at("x") == 100 && first.at("y") == 50 &&
                    second.at("layout") == 1 && second.at("x") == 110 && second.at("y") == 55,
                "Repentance+ HUD binding changed native coordinates or controller identity");
#endif
        field<bool>(hud, hudVisibleOffset) = false;
        lua_State hiddenHud;
        require(presentation::playerHuds(&hiddenHud) == 1 && hiddenHud.tables[0].children.empty(),
                "Hidden native HUD returned stale player anchors");
        presentation::reset();
        require(!presentation::playedIntro() && presentation::intros.empty() &&
                    !presentation::hostIntro && itemResets,
                "Presentation reset retained events or skipped item cleanup");
        require(MH_Uninitialize() == MH_OK, "Remove presentation fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts(
            "PASS versioned intros, event bytes, room barriers, actor ownership and light views");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

namespace isaac::presentation::animation {
bool install(std::uintptr_t) {
    return true;
}
void reset() {}
bool bind(lua_State*, HMODULE) {
    return true;
}
} // namespace isaac::presentation::animation

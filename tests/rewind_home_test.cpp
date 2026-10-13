// Exercise the production hourglass adapter in a private x86 image. Native
// route selection is modelled by ABI callees; no game, save file or hook runs.
#include "test_support.h"
#include "engine/versions/j460/rewind.cpp"
#include <algorithm>
#include <limits>
#include <string>

namespace {
namespace rewind = isaac::rewind;
namespace native = isaac::engine::j460;
using Address = std::uintptr_t;
using Location = isaac::rooms::SavedLocation;
static_assert(sizeof(Address) == 4);
constexpr unsigned imageSize = 0x880000, bufferOffset = 0x269ec;
template <class T> T& field(void* memory, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<std::uint8_t*>(memory) + offset);
}
struct Fixture;
Fixture* current = nullptr;
void __stdcall storeFixture(int);
void __attribute__((thiscall)) wrapperFixture(void*, int, int, int, void*, int);
void __attribute__((thiscall)) lowerFixture(void*, int, int, int, void*, int);
void __attribute__((thiscall)) stageFixture(void*, bool, int, void*);
struct Fixture {
    std::uint8_t* image = nullptr;
    std::vector<std::uint8_t> game = std::vector<std::uint8_t>(0x68000, 0);
    std::array<std::array<std::uint8_t, 0x2200>, 4> players{};
    std::array<Address, 4> roster{};
    std::vector<std::uint8_t> savedBytes{0x31, 0x72, 0x25, 0x19};
    std::vector<Location> locations{{0, 84, 160.5f, 280.25f}, {2, 97, 400.25f, 150.5f}};
    std::vector<std::vector<Location>> resumed;
    std::vector<std::vector<std::uint8_t>> rewindEvents;
    std::vector<std::string> events, aborts;
    std::vector<int> luaResults;
    std::vector<std::uint8_t> luaBytes;
    std::optional<rewind::NativeTransition> lowerExpected;
    bool replica = false, virtualized = true, decodeAllowed = true, storeReady = true;
    bool encodeAllowed = true, homeAtCanonicalStart = true, firstVisit = true,
         prepareAllowed = true;
    bool decisionReturned = false;
    int viewRoom = 97, transitionState = 1, transitionActive = 1;
    std::array<int, 4> sourceRooms{84, 97, 98, 99};
    std::array<bool, 4> sourceFirstVisit{true, false, false, false};
    unsigned difficulty = 0, prepares = 0, cleanups = 0, greedCalls = 0, teleports = 0;
    int specialRoomType = 0, specialRoomStage = 0;
    unsigned userSlot = 1, door = 2, tick = 345;
    unsigned stored = 0, decoded = 0, wrappers = 0, lowerCalls = 0;
    unsigned capturedHomes = 0, stageEvents = 0, nativeStages = 0;
    std::string abiError;

    Fixture() {
        image = static_cast<std::uint8_t*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image != nullptr, "Cannot allocate the private rewind image");
        current = this;
        const auto jump = [&](unsigned offset, auto target) {
            image[offset] = 0xe9;
            field<std::uint32_t>(image, offset + 1) = static_cast<std::uint32_t>(
                reinterpret_cast<Address>(target) - reinterpret_cast<Address>(image + offset + 5));
        };
        jump(native::entry::engineRoomsTransition, wrapperFixture);
        jump(native::entry::engineRoomsStageTransition, stageFixture);
        jump(native::entry::roomTransitionStart, lowerFixture);
        require(FlushInstructionCache(GetCurrentProcess(), image, imageSize) != 0,
                "Cannot publish private rewind ABI trampolines");
        field<Address>(image, native::globals::game) = reinterpret_cast<Address>(game.data());
        for (unsigned slot = 0; slot < 4; ++slot) {
            field<int>(players[slot].data(), 0x1618) = static_cast<int>(slot + 1);
            field<unsigned>(players[slot].data(), 0x1da8) = 31 + slot;
            field<unsigned>(players[slot].data(), 0x1dac) = 7 + slot;
            roster[slot] = reinterpret_cast<Address>(players[slot].data());
        }
        field<Address>(game.data(), 0x1baa8) = reinterpret_cast<Address>(roster.data());
        field<Address>(game.data(), 0x1baac) = reinterpret_cast<Address>(roster.data() + 4);
        field<int>(game.data(), 0x265c0) = 0x12345678;
        field<bool>(game.data(), 0x67744) = true;
        rewind::reset();
        rewind::image = base();
        rewind::originalStore = storeFixture;
        rewind::nativeHome = nullptr;
    }
    ~Fixture() {
        rewind::reset();
        rewind::nativeHome = nullptr;
        rewind::originalStore = nullptr;
        rewind::image = 0;
        rewind::lua = {};
        current = nullptr;
        VirtualFree(image, 0, MEM_RELEASE);
    }
    Address base() const {
        return reinterpret_cast<Address>(image);
    }
    unsigned counter(unsigned i) const {
        return 0x60000000u + 37 * i;
    }
    void reject(const char* message) {
        if (abiError.empty())
            abiError = message;
    }
    void validABI() const {
        require(abiError.empty(), abiError.c_str());
    }
    void clearCalls() {
        events.clear();
        resumed.clear();
        rewindEvents.clear();
        wrappers = lowerCalls = capturedHomes = stageEvents = nativeStages = decoded = 0;
        prepares = cleanups = greedCalls = teleports = 0;
        decisionReturned = false;
    }
    rewind::Checkpoint checkpoint() const {
        rewind::Checkpoint result;
        result.game = savedBytes;
        result.locations = locations;
        result.door = door;
        result.tick = tick;
        for (unsigned i = 0; i < result.counters.size(); ++i)
            result.counters[i] = counter(i);
        return result;
    }
    rewind::NativeTransition requestedTransition() const {
        return {locations[userSlot].index, 0, 12, locations[userSlot].dimension};
    }
    rewind::NativeTransition chosenTransition() const {
        return lowerExpected.value_or(requestedTransition());
    }
    std::vector<std::uint8_t>
    payload(const std::optional<rewind::NativeTransition>& selected = std::nullopt) const {
        return rewind::encode(checkpoint(), userSlot, selected);
    }
    void remember() {
        rewind::remember(userSlot, static_cast<int>(door), locations);
        validABI();
        clearCalls();
    }
    void verifyArguments(void* receiver, bool lower, int index, int direction, int animation,
                         void* player, int dimension) {
        const auto target = lower ? chosenTransition() : requestedTransition();
        if (receiver != game.data() + (lower ? 0x1b83c : 0) || index != target.index ||
            direction != target.direction || animation != target.animation ||
            player != players[userSlot].data() || dimension != target.dimension)
            reject("Room transition thiscall receiver or five stack arguments differ");
        if (field<int>(game.data(), 0x676ac) != 0 || !field<bool>(game.data(), bufferOffset) ||
            field<bool>(game.data(), bufferOffset + 0x20660) ||
            field<unsigned>(game.data(), bufferOffset + 0x1fe2c) != door ||
            field<unsigned>(game.data(), bufferOffset + 0x1fe30) != tick)
            reject("Native rewind buffer flags, door or tick were not restored before transition");
        for (unsigned i = 0; i < 523; ++i)
            if (field<unsigned>(game.data(), bufferOffset + 0x1fe34 + i * 4) != counter(i))
                reject("Native transition saw another checkpoint's counters");
    }
};

bool sameLocations(const std::vector<Location>& a, const std::vector<Location>& b) {
    if (a.size() != b.size())
        return false;
    for (unsigned i = 0; i < a.size(); ++i)
        if (a[i].dimension != b[i].dimension || a[i].index != b[i].index || a[i].x != b[i].x ||
            a[i].y != b[i].y)
            return false;
    return true;
}
void __stdcall storeFixture(int door) {
    auto& f = *current;
    ++f.stored;
    f.events.push_back("store");
    if (door != static_cast<int>(f.door) || field<int>(f.game.data(), 0x676ac) != -1)
        f.reject("Native Store did not receive the checkpoint door and cleared rewind timer");
    field<bool>(f.game.data(), bufferOffset) = f.storeReady;
    field<unsigned>(f.game.data(), bufferOffset + 0x1fe2c) = f.door;
    field<unsigned>(f.game.data(), bufferOffset + 0x1fe30) = f.tick;
    for (unsigned i = 0; i < 523; ++i)
        field<unsigned>(f.game.data(), bufferOffset + 0x1fe34 + i * 4) = f.counter(i);
}
void __attribute__((thiscall)) lowerFixture(void* receiver, int index, int direction, int animation,
                                            void* player, int dimension) {
    auto& f = *current;
    f.verifyArguments(receiver, true, index, direction, animation, player, dimension);
    ++f.lowerCalls;
    f.events.push_back("native-room-start");
    field<int>(f.game.data(), 0x1b83c) = f.transitionState;
    field<int>(f.game.data(), 0x1b83c + 0x238) = f.transitionActive;
    field<int>(f.game.data(), 0x1b83c + 0x14) = index;
    field<int>(f.game.data(), 0x1b83c + 0x10) = direction;
    field<int>(f.game.data(), 0x1b83c + 0x1c) = animation;
    field<int>(f.game.data(), 0x1b83c + 0x18) = dimension;
}
void __attribute__((thiscall)) stageFixture(void* receiver, bool same, int animation,
                                            void* player) {
    auto& f = *current;
    if (receiver != f.game.data() || same || animation != 6 || player != nullptr)
        f.reject("Home stage transition thiscall receiver or three stack arguments differ");
    // This is the rooms stage-hook boundary: route capture precedes any native
    // call or authority policy, including on the replica.
    if (rewind::captureStage(same, animation)) {
        ++f.capturedHomes;
        f.events.push_back("capture-home");
        return;
    }
    ++f.nativeStages;
    f.events.push_back("native-home");
    if (!f.decisionReturned || f.replica || f.stageEvents != 1)
        f.reject("Home executed before the decision/event or executed on a rewind replica");
}
void __attribute__((thiscall)) wrapperFixture(void* receiver, int index, int direction,
                                              int animation, void* player, int dimension) {
    auto& f = *current;
    f.verifyArguments(receiver, false, index, direction, animation, player, dimension);
    ++f.wrappers;
    f.events.push_back("native-route-decision");
    if (f.specialRoomType == 16 || f.specialRoomStage == 35) {
        // These native room branches teleport in place and return without
        // starting RoomTransition. The authority must publish that absence.
        ++f.teleports;
        field<int>(f.game.data(), 0x1b83c) = 0;
        f.events.push_back("native-local-teleport");
    } else if (f.difficulty < 2 && f.homeAtCanonicalStart && f.firstVisit && f.viewRoom == 84) {
        using Stage = void(__attribute__((thiscall))*)(void*, bool, int, void*);
        reinterpret_cast<Stage>(f.base() + native::entry::engineRoomsStageTransition)(
            receiver, false, 6, nullptr);
    } else {
        if (f.difficulty >= 2 && f.firstVisit && f.viewRoom == 84) {
            ++f.greedCalls;
            f.events.push_back("native-greed-special");
            f.lowerExpected = rewind::NativeTransition{-2, 0, 3, 0};
        }
        const auto selected = f.chosenTransition();
        using Transition = void(__attribute__((thiscall))*)(void*, int, int, int, void*, int);
        reinterpret_cast<Transition>(f.base() + native::entry::roomTransitionStart)(
            f.game.data() + 0x1b83c, selected.index, selected.direction, selected.animation, player,
            selected.dimension);
        if (f.transitionState && f.transitionActive)
            field<int>(f.game.data(), 0x265c0) = 0;
        field<bool>(f.game.data(), 0x67744) = false;
    }
    f.decisionReturned = true;
    f.events.push_back("native-route-return");
}
} // namespace

namespace isaac::rooms {
bool virtualized() {
    return current->virtualized;
}
void beforeStart() {
    current->events.push_back("before-start");
    ++current->cleanups;
    current->virtualized = false;
}
bool prepareRewind(unsigned slot) {
    auto& f = *current;
    ++f.prepares;
    f.events.push_back("prepare-source");
    if (slot != f.userSlot)
        f.reject("Host prepared a different player's source room");
    if (!f.prepareAllowed)
        return false;
    f.viewRoom = f.sourceRooms[slot];
    f.firstVisit = f.sourceFirstVisit[slot];
    beforeStart();
    return true;
}
void resumeAfterTransition(std::vector<SavedLocation> locations) {
    current->events.push_back("resume");
    current->resumed.push_back(std::move(locations));
}
} // namespace isaac::rooms
namespace isaac::save {
std::vector<std::uint8_t> encodeAt(Address image, Address state) {
    auto& f = *current;
    if (image != f.base() || state != reinterpret_cast<Address>(f.game.data()) + bufferOffset + 4)
        f.reject("Checkpoint serializer received the wrong image or embedded GameState");
    return f.encodeAllowed ? f.savedBytes : std::vector<std::uint8_t>{};
}
bool decodeAt(Address image, Address state, std::span<const std::uint8_t> bytes) {
    auto& f = *current;
    ++f.decoded;
    f.events.push_back("decode");
    if (image != f.base() || state != reinterpret_cast<Address>(f.game.data()) + bufferOffset + 4 ||
        !std::equal(bytes.begin(), bytes.end(), f.savedBytes.begin(), f.savedBytes.end()))
        f.reject("Checkpoint restore received the wrong image, GameState or payload");
    return f.decodeAllowed;
}
} // namespace isaac::save
namespace isaac::runtime {
bool replica() {
    return current->replica;
}
void beginStage(bool same, int animation, unsigned restart, unsigned cinematic) {
    auto& f = *current;
    if (same || animation != 6 || restart || cinematic || !f.decisionReturned ||
        !f.rewindEvents.empty() || f.nativeStages || !f.resumed.empty())
        f.reject("Home publication preceded the decision or mixed with a rewind transaction");
    ++f.stageEvents;
    f.events.push_back("publish-home");
}
void beginRewind(std::span<const std::uint8_t> bytes) {
    auto& f = *current;
    if (!f.decisionReturned || f.stageEvents || f.nativeStages || f.replica || !f.resumed.empty())
        f.reject("Rewind publication preceded the native decision or mixed with Home");
    f.rewindEvents.emplace_back(bytes.begin(), bytes.end());
    f.events.push_back("publish-rewind");
}
void abort(const std::string& reason) {
    current->aborts.push_back(reason);
}
} // namespace isaac::runtime

namespace {
void homeTransaction() {
    Fixture f;
    f.sourceRooms[0] = 97;
    f.sourceRooms[1] = 84;
    f.sourceFirstVisit[0] = false;
    f.sourceFirstVisit[1] = true;
    const auto playersBefore = f.players;
    f.remember();
    require(f.viewRoom == 97 && f.sourceRooms[1] == 84,
            "Missing requester Home regression fixture");
    require(rewind::request(1) && rewind::executePending(),
            "Host did not execute remembered P2 rewind");
    f.validABI();
    require(f.events == std::vector<std::string>{"prepare-source", "before-start", "decode",
                                                 "native-route-decision", "capture-home",
                                                 "native-route-return", "publish-home",
                                                 "native-home", "resume"},
            "Host Home route/event/native execution order differs");
    require(f.stageEvents == 1 && f.nativeStages == 1 && f.capturedHomes == 1 &&
                f.lowerCalls == 0 && f.rewindEvents.empty() && f.prepares == 1 && f.cleanups == 1,
            "Host published both Home and rewind, or executed an early room transition");
    require(f.resumed.size() == 1 && f.resumed.front().empty(),
            "Home departure restored obsolete old-floor player locations");
    require(f.players == playersBefore && !rewind::captureStage(false, 6),
            "Home branch changed actor ownership or leaked its capture scope");
    require(!rewind::executePending(), "Consumed Home request was replayed");
}
void normalTransaction() {
    Fixture f;
    f.viewRoom = 84; // P1's initial room must not select Home for P2 in 97.
    f.remember();
    const auto expected = f.payload(f.chosenTransition());
    require(rewind::request(1) && rewind::executePending(), "Ordinary rewind did not execute");
    f.validABI();
    require(f.events == std::vector<std::string>{"prepare-source", "before-start", "decode",
                                                 "native-route-decision", "native-room-start",
                                                 "native-route-return", "publish-rewind", "resume"},
            "Ordinary rewind was published before the native route decision completed");
    require(f.rewindEvents.size() == 1 && f.rewindEvents.front() == expected &&
                f.stageEvents == 0 && f.nativeStages == 0 && f.resumed.size() == 1 &&
                sameLocations(f.resumed[0], f.locations) && f.viewRoom == 97 && f.prepares == 1 &&
                f.cleanups == 1,
            "Ordinary rewind changed its exact wire payload or restored player positions");
}
void replicaHomeFallback() {
    for (unsigned difficulty : {0, 1})
        for (int state : {0, 1})
            for (int active : {0, 1}) {
                Fixture f;
                f.replica = true;
                f.difficulty = difficulty;
                f.viewRoom = 84;
                f.transitionState = state;
                f.transitionActive = active;
                const auto bytes = f.payload(f.chosenTransition());
                field<unsigned>(f.players[1].data(), 0x1da8) = 900;
                field<unsigned>(f.players[1].data(), 0x1dac) = 800;
                require(rewind::startRewind(bytes), "Replica rejected the host's ordinary rewind");
                f.validABI();
                require(f.events == std::vector<std::string>{"before-start", "decode",
                                                             "native-room-start", "resume"},
                        "Replica did not bypass its conflicting local Home route using "
                        "RoomTransition.Start");
                require(f.wrappers == 0 && f.capturedHomes == 0 && f.lowerCalls == 1 &&
                            f.stageEvents == 0 && f.nativeStages == 0 && f.rewindEvents.empty() &&
                            f.prepares == 0 && f.cleanups == 1,
                        "Replica reselected Home or emitted an authoritative event");
                require(field<int>(f.game.data(), 0x265c0) == (state && active ? 0 : 0x12345678) &&
                            !field<bool>(f.game.data(), 0x67744),
                        "Replica fallback did not reproduce the native wrapper's conditional tail "
                        "flags");
                require(
                    field<unsigned>(f.players[1].data(), 0x1da8) == 32 &&
                        field<unsigned>(f.players[1].data(), 0x1dac) == 8 &&
                        f.resumed.size() == 1 && sameLocations(f.resumed[0], f.locations),
                    "Replica lost authoritative hourglass charges or per-player target locations");
            }
}
void replicaNormalAndPartySizes() {
    for (unsigned count = 2; count <= 4; ++count) {
        Fixture f;
        f.replica = true;
        while (f.locations.size() < count)
            f.locations.push_back({1, static_cast<int>(100 + f.locations.size()), 200.f, 300.f});
        f.userSlot = count - 1;
        require(rewind::startRewind(f.payload(f.chosenTransition())),
                "Valid party-sized rewind failed");
        f.validABI();
        require(f.wrappers == 0 && f.lowerCalls == 1 && f.capturedHomes == 0 &&
                    f.stageEvents == 0 && f.nativeStages == 0 && f.rewindEvents.empty() &&
                    f.resumed.size() == 1 && sameLocations(f.resumed[0], f.locations),
                "Replica repeated a normal native transition or changed its 2/3/4-player roster");
    }
}
void greedReplaysAuthoritySelection() {
    for (unsigned difficulty : {2, 3}) {
        Fixture f;
        f.difficulty = difficulty;
        f.viewRoom = f.sourceRooms[1] = 84;
        f.sourceFirstVisit[1] = true;
        require(rewind::startRewind(f.payload()), "Host Greed native rewind failed");
        f.validABI();
        require(f.wrappers == 1 && f.greedCalls == 1 && f.lowerCalls == 1 && f.capturedHomes == 0 &&
                    f.stageEvents == 0 && f.nativeStages == 0 && f.rewindEvents.size() == 1 &&
                    f.rewindEvents[0] == f.payload(rewind::NativeTransition{-2, 0, 3, 0}),
                "Host did not publish Greed's actual teleport choice");
        const auto wire = f.rewindEvents[0];
        f.clearCalls();
        f.replica = true;
        f.viewRoom = 97; // A conflicting guest viewport must not reselect the route.
        require(rewind::startRewind(wire), "Replica rejected Greed's actual native choice");
        f.validABI();
        require(f.wrappers == 0 && f.greedCalls == 0 && f.lowerCalls == 1 && f.stageEvents == 0 &&
                    f.nativeStages == 0 && f.rewindEvents.empty() && f.resumed.size() == 1 &&
                    sameLocations(f.resumed[0], f.locations),
                "Greed replica reran the native wrapper instead of replaying index -2/animation "
                "3/dimension 0");
    }
}
void nativeEarlyReturn() {
    for (int branch : {16, 35}) {
        Fixture f;
        f.specialRoomType = branch == 16 ? 16 : 0;
        f.specialRoomStage = branch == 35 ? 35 : 0;
        field<int>(f.game.data(), 0x1b83c) = 1;
        require(rewind::startRewind(f.payload()), "Host native early-return route failed");
        f.validABI();
        require(f.wrappers == 1 && f.teleports == 1 && f.lowerCalls == 0 &&
                    f.rewindEvents.size() == 1 && f.rewindEvents[0] == f.payload() &&
                    f.resumed.size() == 1 && sameLocations(f.resumed[0], f.locations),
                "Native in-place teleport became a fabricated room transition");
        const auto wire = f.rewindEvents[0];
        f.clearCalls();
        f.replica = true;
        f.viewRoom = 84;
        f.specialRoomType = f.specialRoomStage = 0;
        // Inactive selection must not infer a transition from replica memory.
        field<int>(f.game.data(), 0x1b83c) = 1;
        field<int>(f.game.data(), 0x265c0) = 0x12345678;
        field<bool>(f.game.data(), 0x67744) = true;
        require(rewind::startRewind(wire), "Replica rejected the authority's inactive choice");
        f.validABI();
        require(f.events == std::vector<std::string>{"before-start", "decode", "resume"} &&
                    f.wrappers == 0 && f.lowerCalls == 0 && f.teleports == 0 &&
                    f.stageEvents == 0 && f.resumed.size() == 1 &&
                    sameLocations(f.resumed[0], f.locations) &&
                    field<int>(f.game.data(), 0x265c0) == 0x12345678 &&
                    field<bool>(f.game.data(), 0x67744),
                "Inactive replica choice started a transition instead of adopting the "
                "authoritative checkpoint");
    }
}
void actualNativeParameters() {
    Fixture f;
    f.lowerExpected = rewind::NativeTransition{103, 7, 22, 1};
    const auto requested = f.payload();
    require(rewind::startRewind(requested), "Host native redirected rewind failed");
    f.validABI();
    require(f.rewindEvents.size() == 1 && f.rewindEvents[0] != requested &&
                f.rewindEvents[0] == f.payload(f.chosenTransition()),
            "Host republished requested arguments instead of the native selected fields");
    const auto wire = f.rewindEvents[0];
    f.clearCalls();
    f.replica = true;
    require(rewind::startRewind(wire), "Replica rejected the chosen native parameters");
    f.validABI();
    require(f.wrappers == 0 && f.lowerCalls == 1, "Replica reran native parameter selection");
}
void sourcePreparationFailure() {
    Fixture f;
    f.remember();
    f.prepareAllowed = false;
    const auto gameBefore = f.game;
    const auto playersBefore = f.players;
    require(rewind::request(1), "Known checkpoint could not be requested");
    rejects([&] { rewind::executePending(); }, "Missing authoritative source room was accepted");
    require(f.events == std::vector<std::string>{"prepare-source"} && f.prepares == 1 &&
                f.cleanups == 0 && f.decoded == 0 && f.wrappers == 0 && f.resumed.empty() &&
                f.rewindEvents.empty() && f.stageEvents == 0 && f.game == gameBefore &&
                f.players == playersBefore,
            "Failed source preparation cleaned up rooms, restored state or published an event");
    require(!rewind::executePending() && !rewind::captureStage(false, 6),
            "Failed request retained a pending transaction or route capture");
    f.clearCalls();
    f.prepareAllowed = true;
    require(rewind::request(1) && rewind::executePending() && f.prepares == 1 && f.cleanups == 1 &&
                f.rewindEvents.size() == 1,
            "Source preparation failure destroyed the reusable checkpoint");
    f.validABI();
}
void nestedCapture() {
    Fixture f;
    require(!rewind::captureStage(false, 6),
            "Ordinary Home transition was intercepted without a rewind");
    bool outer = false, inner = false;
    {
        rewind::RouteScope outerScope(outer);
        for (const auto& values :
             std::array<std::pair<bool, int>, 4>{{{true, 6}, {false, 0}, {false, 12}, {true, 0}}})
            require(!rewind::captureStage(values.first, values.second) && !outer,
                    "A normal stage request was swallowed by a rewind route scope");
        {
            rewind::RouteScope innerScope(inner);
            require(rewind::captureStage(false, 6) && inner && !outer,
                    "Nested capture changed the enclosing route result");
        }
        require(rewind::captureStage(false, 6) && outer,
                "Nested route scope did not restore its parent");
        outer = false;
        rejects(
            [&] {
                bool throwing = false;
                rewind::RouteScope throwingScope(throwing);
                require(rewind::captureStage(false, 6) && throwing,
                        "Throwing scope failed to capture Home");
                throw std::runtime_error("fixture unwind");
            },
            "Scope exception was lost");
        require(rewind::captureStage(false, 6) && outer,
                "Exception unwinding lost the parent capture pointer");
        outer = false;
        rewind::reset();
        require(rewind::captureStage(false, 6) && outer,
                "Checkpoint reset damaged an active lexical capture scope");
    }
    require(!rewind::captureStage(false, 6) && rewind::nativeHome == nullptr,
            "Capture pointer remained armed after the outer scope ended");
}
void repeatAndReset() {
    Fixture f;
    f.sourceRooms[1] = 84;
    f.sourceFirstVisit[1] = true;
    require(!rewind::request(1) && !rewind::executePending(), "Missing checkpoint was executable");
    f.remember();
    require(!rewind::request(4) && rewind::request(1) && rewind::request(1),
            "Invalid slot or duplicate pending request changed the checkpoint contract");
    rewind::remember(0, f.door, f.locations);
    require(!rewind::request(0), "Another player replaced the pending hourglass user");
    f.clearCalls();
    require(rewind::executePending() && f.stageEvents == 1 && !rewind::executePending(),
            "Pending request was duplicated or lost");
    f.clearCalls();
    f.homeAtCanonicalStart = false;
    require(rewind::request(1) && rewind::executePending() && f.capturedHomes == 0 &&
                f.rewindEvents.size() == 1 && f.nativeStages == 0,
            "An earlier Home result leaked into a repeated ordinary rewind");
    f.clearCalls();
    require(rewind::request(1), "Checkpoint was consumed instead of retained");
    rewind::reset();
    require(!rewind::executePending() && !rewind::request(0) && !rewind::request(1) &&
                f.events.empty(),
            "Reset retained a pending request or another controller's checkpoint");
    f.validABI();
}
void nativeHomeSourceGuards() {
    const auto eligible = isaac::compat::routes::hourglassHomeSource;
    // Ordinary and alternate first-floor skins share the native entrance;
    // the two Repentance stage types have their own route and must be excluded.
    for (int stageType : {0, 1, 2, 3, 6})
        for (int difficulty : {0, 1})
            for (int startingRoom : {0, 84, 105, 168})
                require(eligible(1, stageType, difficulty, startingRoom, startingRoom, true),
                        "Eligible native Home source was rejected or hard-coded to room 84");
    for (int stage : {-1, 0, 2, 3, 8, 13, std::numeric_limits<int>::max()})
        require(!eligible(stage, 0, 0, 84, 84, true),
                "A non-first floor was allowed to use the missing-checkpoint Home path");
    for (int stageType : {4, 5})
        for (int difficulty : {0, 1})
            require(!eligible(1, stageType, difficulty, 84, 84, true),
                    "A Repentance first-floor route was treated as native Home");
    for (int difficulty : {2, 3})
        for (int stageType : {0, 1, 2, 3, 4, 5})
            require(!eligible(1, stageType, difficulty, 84, 84, true),
                    "Greed/Greedier entered the missing-checkpoint Home path");
    for (int room : {-20, 0, 83, 85, 97, 168})
        require(!eligible(1, 0, 0, room, 84, true),
                "Another player's starting room authorized this user's Home route");
    for (int startingRoom : {0, 84, 105, 168})
        for (int difficulty : {0, 1})
            require(!eligible(1, 0, difficulty, startingRoom, startingRoom, false),
                    "Re-entered starting room was treated as a first native visit");
}
void cancelPreservesCheckpoints() {
    Fixture f;
    f.homeAtCanonicalStart = false;
    f.locations.push_back({0, 105, 200.f, 300.f});
    f.locations.push_back({1, 118, 250.f, 300.f});
    const auto selectCheckpoint = [&](unsigned slot) {
        f.userSlot = slot;
        f.door = slot + 1;
        f.tick = 345 + slot;
        f.savedBytes = {static_cast<std::uint8_t>(slot + 1), 0x72, 0x25, 0x19};
    };
    for (unsigned slot = 0; slot < 4; ++slot) {
        selectCheckpoint(slot);
        f.remember();
    }
    require(rewind::request(1) && !rewind::request(2), "Fixture did not retain one pending owner");
    rewind::cancelPending();
    rewind::cancelPending();
    require(!rewind::executePending() && f.events.empty(),
            "Cancel replayed a pending rewind or touched native state");
    require(rewind::request(2), "Cancel left another controller blocked by the old pending owner");
    rewind::cancelPending();
    for (unsigned slot = 0; slot < 4; ++slot) {
        selectCheckpoint(slot);
        f.clearCalls();
        require(rewind::request(slot) && rewind::executePending(),
                "Cancel destroyed one of the four controllers' saved checkpoints");
        f.validABI();
        require(f.rewindEvents.size() == 1 &&
                    f.rewindEvents[0] == f.payload(f.chosenTransition()) && f.resumed.size() == 1 &&
                    sameLocations(f.resumed[0], f.locations),
                "Cancel replaced a retained checkpoint's native bytes, tick or locations");
    }
    f.clearCalls();
    bool home = false;
    {
        rewind::RouteScope scope(home);
        rewind::cancelPending();
        require(rewind::captureStage(false, 6) && home,
                "Cancel reset unrelated active native route capture");
    }
    require(!rewind::executePending() && f.events.empty() && !rewind::captureStage(false, 6),
            "Idle cancel leaked a pending request or route scope");
}
void storeBoundary() {
    Fixture f;
    rewind::store(f.door);
    require(f.stored == 0, "Virtual room entry replaced the process-wide native checkpoint");
    f.virtualized = false;
    field<int>(f.game.data(), 0x676ac) = -1;
    rewind::store(f.door);
    require(f.stored == 1, "Ordinary native room entry stopped forwarding Store");
    f.replica = true;
    rewind::remember(1, f.door, f.locations);
    require(f.stored == 1 && !rewind::request(1),
            "Replica captured an authoritative rewind checkpoint");
    f.replica = false;
    rewind::remember(4, f.door, f.locations);
    rewind::remember(1, f.door, {});
    require(f.stored == 1, "Invalid capture input reached native Store");
    f.storeReady = false;
    rewind::remember(1, f.door, f.locations);
    require(!rewind::request(1), "Unready native checkpoint became requestable");
    f.storeReady = true;
    f.encodeAllowed = false;
    rejects([&] { rewind::remember(1, f.door, f.locations); },
            "Empty checkpoint serialization was accepted");
    f.validABI();
}

void rehash(std::vector<std::uint8_t>& bytes) {
    const auto hash = isaac::lan::snapshotHash(std::span(bytes).first(bytes.size() - 8));
    for (unsigned i = 0; i < 8; ++i)
        bytes[bytes.size() - 8 + i] = static_cast<std::uint8_t>(hash >> ((7 - i) * 8));
}
void put32(std::vector<std::uint8_t>& bytes, unsigned offset, std::uint32_t value) {
    for (unsigned i = 0; i < 4; ++i)
        bytes[offset + i] = static_cast<std::uint8_t>(value >> ((3 - i) * 8));
}
void malformedPayloads() {
    Fixture f;
    const auto good = f.payload();
    const auto gameBefore = f.game;
    const auto playersBefore = f.players;
    const auto reject = [&](const std::vector<std::uint8_t>& bytes) {
        require(!rewind::startRewind(bytes), "Invalid rewind payload reached native transition");
        require(f.events.empty() && f.game == gameBefore && f.players == playersBefore,
                "Malformed rewind mutated native state before validation finished");
    };
    reject({});
    reject({1, 2, 3, 4, 5, 6, 7});
    auto bytes = good;
    bytes.back() ^= 1;
    reject(bytes);
    constexpr unsigned countOffset = 2 + 4 * 4 + 523 * 4;
    for (const auto& change : std::array<std::pair<unsigned, unsigned>, 6>{
             {{0, 255}, {1, 4}, {countOffset, 0}, {countOffset, 1}, {countOffset, 5}, {1, 2}}}) {
        bytes = good;
        bytes[change.first] = change.second;
        rehash(bytes);
        reject(bytes);
    }
    constexpr unsigned locationOffset = countOffset + 1;
    for (const auto& change : std::array<std::pair<unsigned, std::uint32_t>, 8>{
             {{0, static_cast<unsigned>(-1)},
              {0, 3},
              {4, static_cast<unsigned>(-21)},
              {4, 169},
              {8, std::bit_cast<unsigned>(std::numeric_limits<float>::infinity())},
              {12, std::bit_cast<unsigned>(std::numeric_limits<float>::quiet_NaN())},
              {16, 3},
              {20, 169}}}) {
        bytes = good;
        put32(bytes, locationOffset + change.first, change.second);
        rehash(bytes);
        reject(bytes);
    }
    bytes = good;
    bytes.erase(bytes.end() - 9);
    rehash(bytes);
    rejects([&] { rewind::startRewind(bytes); }, "Truncated authenticated checkpoint was accepted");
    bytes = good;
    bytes.insert(bytes.end() - 8, 0);
    rehash(bytes);
    rejects([&] { rewind::startRewind(bytes); },
            "Trailing authenticated checkpoint data was accepted");
    require(f.events.empty() && f.game == gameBefore && f.players == playersBefore,
            "Reader failure reached native restoration");
}
void selectedPayloadBounds() {
    Fixture f;
    f.replica = true;
    const auto valid = f.payload(f.chosenTransition());
    const auto offset = valid.size() - 8 - 17;
    const auto gameBefore = f.game;
    const auto playersBefore = f.players;
    auto bytes = valid;
    bytes[offset] = 2;
    rehash(bytes);
    require(!rewind::startRewind(bytes), "Nonboolean native-selection marker was accepted");
    for (const auto& invalid : std::array<std::pair<unsigned, int>, 8>{
             {{0, -21}, {0, 169}, {4, -2}, {4, 8}, {8, -1}, {8, 23}, {12, -1}, {12, 3}}}) {
        bytes = valid;
        put32(bytes, offset + 1 + invalid.first, static_cast<unsigned>(invalid.second));
        rehash(bytes);
        require(!rewind::startRewind(bytes),
                "Out-of-range selected native parameters were accepted");
    }
    for (unsigned length = 0; length < 16; ++length) {
        bytes = valid;
        bytes.erase(bytes.begin() + offset + 1 + length, bytes.end() - 8);
        rehash(bytes);
        rejects([&] { rewind::startRewind(bytes); },
                "Truncated selected native parameters were accepted");
    }
    bytes = valid;
    bytes[offset] = 0;
    rehash(bytes);
    rejects([&] { rewind::startRewind(bytes); },
            "Inactive choice accepted trailing native arguments");
    require(f.events.empty() && f.game == gameBefore && f.players == playersBefore,
            "Invalid selected native parameters reached checkpoint restoration");
    for (int index : {-20, 168})
        for (int direction : {-1, 7})
            for (int animation : {0, 22})
                for (int dimension : {0, 2}) {
                    f.clearCalls();
                    f.lowerExpected =
                        rewind::NativeTransition{index, direction, animation, dimension};
                    require(rewind::startRewind(f.payload(f.lowerExpected)),
                            "Valid boundary native parameters were rejected");
                    f.validABI();
                    require(f.wrappers == 0 && f.lowerCalls == 1 && f.resumed.size() == 1,
                            "Valid boundary parameters did not reach the original lower callee");
                }
}
void invalidNativeSelection() {
    Fixture f;
    f.lowerExpected = rewind::NativeTransition{169, 0, 12, 0};
    rejects([&] { rewind::startRewind(f.payload()); }, "Invalid host native choice was published");
    f.validABI();
    require(f.wrappers == 1 && f.lowerCalls == 1 && f.rewindEvents.empty() && f.stageEvents == 0 &&
                f.resumed.empty() && !rewind::captureStage(false, 6),
            "Invalid native selection leaked an event, resume or route-capture scope");
}
void restorationFailures() {
    Fixture f;
    const auto bytes = f.payload();
    f.decodeAllowed = false;
    require(!rewind::startRewind(bytes) &&
                f.events == std::vector<std::string>{"prepare-source", "before-start", "decode"} &&
                f.rewindEvents.empty() && f.stageEvents == 0 && f.resumed.empty(),
            "Failed GameState restore emitted an event or resumed an invalid checkpoint");
    f.clearCalls();
    f.decodeAllowed = true;
    field<unsigned>(f.players[1].data(), 0x2c) = 1;
    require(!rewind::startRewind(bytes) && f.wrappers == 0 && f.rewindEvents.empty() &&
                f.stageEvents == 0 && f.resumed.empty(),
            "Missing real hourglass user was replaced by a child actor or published a rewind");
    rejects([&] { f.payload(); }, "Host encoded a checkpoint without its real user");
    require(!rewind::captureStage(false, 6), "Restore failure leaked a Home capture scope");
    f.validABI();
}
const char* __cdecl luaString(lua_State*, int argument, std::size_t* size) {
    require(argument == 1 && size, "Lua rewind payload argument differs");
    *size = current->luaBytes.size();
    return reinterpret_cast<const char*>(current->luaBytes.data());
}
void __cdecl luaBoolean(lua_State*, int value) {
    current->luaResults.push_back(value);
}
void luaPayloadFence() {
    Fixture f;
    rewind::lua.checkString = luaString;
    rewind::lua.pushBoolean = luaBoolean;
    f.luaBytes = f.payload();
    require(rewind::beginLua(nullptr) == 1 && f.luaResults == std::vector<int>{0} &&
                f.events.empty(),
            "Host accepted replica-only Lua rewind input");
    f.replica = true;
    f.luaBytes.back() ^= 1;
    require(rewind::beginLua(nullptr) == 1 && f.luaResults.back() == 0 && f.aborts.empty() &&
                f.events.empty(),
            "Bad checksum reached a native call or became an uncaught Lua error");
    f.luaBytes = f.payload();
    f.luaBytes.erase(f.luaBytes.begin() + 20, f.luaBytes.end() - 8);
    rehash(f.luaBytes);
    require(rewind::beginLua(nullptr) == 1 && f.luaResults.back() == 0 && f.aborts.size() == 1 &&
                f.events.empty(),
            "Authenticated truncated Lua payload escaped the abort/false boundary");
}
} // namespace

int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"host-home-transaction", homeTransaction},
                     {"host-normal-transaction", normalTransaction},
                     {"replica-home-fallback", replicaHomeFallback},
                     {"replica-party-sizes", replicaNormalAndPartySizes},
                     {"greed-authority-selection", greedReplaysAuthoritySelection},
                     {"native-early-return", nativeEarlyReturn},
                     {"native-selected-parameters", actualNativeParameters},
                     {"source-preparation-failure", sourcePreparationFailure},
                     {"nested-capture", nestedCapture},
                     {"repeat-reset", repeatAndReset},
                     {"native-home-source-guards", nativeHomeSourceGuards},
                     {"cancel-preserves-checkpoints", cancelPreservesCheckpoints},
                     {"store-boundary", storeBoundary},
                     {"malformed-payloads", malformedPayloads},
                     {"selected-payload-bounds", selectedPayloadBounds},
                     {"invalid-native-selection", invalidNativeSelection},
                     {"restoration-failures", restorationFailures},
                     {"lua-payload-fence", luaPayloadFence}});
}

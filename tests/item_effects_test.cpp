// Private x86 image only: no game process, files, input or hooks are installed.
#include "test_support.h"
#include "engine/versions/j460/item_effects.cpp"
#include "engine/versions/j460/pickup_preview.cpp"
#include "engine/versions/j460/session_backend.cpp"
#include "runtime/progression.h"
#include <array>
#include <cstring>

namespace isaac::runtime {
bool replica() {
    return false;
}
bool divertPickup = false;
unsigned pickupCalls = 0;
bool takeCollectiblePickup(int owner, unsigned seed, int id, int charge, bool touched, int data,
                           int pool) {
    require(owner == 1 && seed == 123 && id == 12 && charge == 7 && touched && data == 9 &&
                pool == 10,
            "Confirmed pickup lost owner, seed, charge or per-item data");
    ++pickupCalls;
    return divertPickup;
}
} // namespace isaac::runtime

namespace isaac::rooms {
bool previewReady = true, localPreviewRoster = false;
bool revivalScoped = false, scopeAvailable = true;
unsigned revivalSlot = 0;
bool withPlayer(unsigned slot, const std::function<void()>& call) {
    if (!scopeAvailable)
        return false;
    revivalSlot = slot;
    revivalScoped = true;
    call();
    revivalScoped = false;
    return true;
}
bool viewReady() {
    return previewReady;
}
bool virtualized() {
    return true;
}
unsigned connected() {
    return 15;
}
std::uintptr_t presentationPlayer(void*) {
    throw std::runtime_error("Item ABI fixture must not execute console commands");
}
void withView(const std::function<void()>& draw, bool localPlayersOnly) {
    require(localPlayersOnly, "Preview queried another player's inventory");
    localPreviewRoster = true;
    draw();
    localPreviewRoster = false;
}
} // namespace isaac::rooms

namespace {
namespace items = isaac::engine::items;
namespace native = isaac::engine::j460;
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
std::vector<int> grants;
unsigned removals = 0, detachments = 0;
void* expectedPlayer;
void* expectedBeam;
void __attribute__((thiscall)) addFixture(void* player, int id, int charge, bool first, int slot,
                                          int data, int unknown) {
    require(player == expectedPlayer && charge == -1 && first && slot == 0 && data == 0 &&
                unknown == 0,
            "Native AddCollectible ABI or receiver changed");
    grants.push_back(id);
}
void __attribute__((thiscall)) removeFixture(void* entity) {
    require(entity == expectedBeam, "Removed an unrelated entity");
    ++removals;
}
void __attribute__((fastcall)) assignFixture(void* reference, void* entity) {
    require(reference == static_cast<unsigned char*>(expectedPlayer) +
                             native::layout::player::megaBlastLaser &&
                !entity,
            "Native EntityPtr ABI or reference changed");
    require(removals == detachments + 1, "Detached before removing the departure laser");
    *static_cast<Address*>(reference) = 0;
    ++detachments;
}
struct Fixture {
    static constexpr unsigned size = native::globals::manager + sizeof(Address);
    unsigned char* image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    std::array<unsigned char, 0x2000> player{};
    std::array<unsigned char, 0x1000> manager{};
    std::array<Address, 11> vtable{};
    Address beam = reinterpret_cast<Address>(vtable.data());
    Fixture() {
        require(image != nullptr, "Cannot allocate the private ABI image");
        items::image = reinterpret_cast<Address>(image);
        items::originalAdd = addFixture;
        expectedPlayer = player.data();
        expectedBeam = &beam;
        grants.clear();
        removals = detachments = 0;
        vtable[native::layout::entity::removeMethod / sizeof(Address)] =
            reinterpret_cast<Address>(removeFixture);
        // thiscall wrapper: load item, push six AddCollectible arguments,
        // call the real hook with its audited return address, then ret 4.
        const unsigned char setup[] = {0x8b, 0x44, 0x24, 0x04, 0x6a, 0,    0x6a, 0,
                                       0x6a, 0,    0x6a, 1,    0x6a, 0xff, 0x50};
        auto call = image + native::entry::edensBlessingGranted - 5;
        std::memcpy(call - sizeof(setup), setup, sizeof(setup));
        call[0] = 0xe8;
        const auto displacement = static_cast<unsigned>(reinterpret_cast<Address>(items::add) -
                                                        reinterpret_cast<Address>(call + 5));
        std::memcpy(call + 1, &displacement, 4);
        call[5] = 0xc2;
        call[6] = 4;
        call[7] = 0;
        auto assign = image + native::entry::entityPtrAssign;
        assign[0] = 0xe9;
        const auto target = static_cast<unsigned>(reinterpret_cast<Address>(assignFixture) -
                                                  reinterpret_cast<Address>(assign + 5));
        std::memcpy(assign + 1, &target, 4);
        require(FlushInstructionCache(GetCurrentProcess(), image, size) != 0,
                "Cannot publish private native call sites");
    }
    ~Fixture() {
        items::image = 0;
        items::originalAdd = nullptr;
        VirtualFree(image, 0, MEM_RELEASE);
    }
    void nativeReward(int item) {
        using Grant = void(__attribute__((thiscall))*)(void*, int);
        reinterpret_cast<Grant>(image + native::entry::edensBlessingGranted - 20)(player.data(),
                                                                                  item);
    }
};
unsigned nativeQueues = 0;
void __attribute__((thiscall)) queueFixture(void* player, void* config, int charge,
                                            unsigned char flags, int data, int pool) {
    require(player == expectedPlayer && config && charge == 7 && flags == 1 && data == 9 &&
                pool == 10,
            "Native QueueItem ABI changed");
    ++nativeQueues;
}
void collectiblePickup() {
    Fixture f;
    items::originalQueue = queueFixture;
    nativeQueues = isaac::runtime::pickupCalls = 0;
    *reinterpret_cast<int*>(f.player.data() + native::layout::player::controller) = 2;
    *reinterpret_cast<unsigned*>(f.player.data() + native::layout::entity::initSeed) = 123;
    std::array<int, 2> config{1, 12};
    const unsigned char setup[] = {0x8b, 0x44, 0x24, 0x04, 0x6a, 10,  0x6a,
                                   9,    0x6a, 1,    0x6a, 7,    0x50};
    auto call = f.image + native::entry::pickupQueuedCollectible - 5;
    std::memcpy(call - sizeof(setup), setup, sizeof(setup));
    call[0] = 0xe8;
    const auto delta = static_cast<unsigned>(reinterpret_cast<Address>(items::queue) -
                                             reinterpret_cast<Address>(call + 5));
    std::memcpy(call + 1, &delta, 4);
    call[5] = 0xc2;
    call[6] = 4;
    call[7] = 0;
    require(FlushInstructionCache(GetCurrentProcess(), f.image, Fixture::size) != 0,
            "Cannot publish the pickup queue call site");
    using Acquire = void(__attribute__((thiscall))*)(void*, void*);
    auto acquire = reinterpret_cast<Acquire>(call - sizeof(setup));
    isaac::runtime::divertPickup = true;
    acquire(f.player.data(), config.data());
    require(isaac::runtime::pickupCalls == 1 && nativeQueues == 0,
            "Intercepted pickup was also granted to its collector");
    isaac::runtime::divertPickup = false;
    acquire(f.player.data(), config.data());
    require(isaac::runtime::pickupCalls == 2 && nativeQueues == 1,
            "Ordinary pickup was swallowed by the challenge hook");
    isaac::runtime::divertPickup = true;
    config[0] = native::layout::itemConfig::trinket;
    acquire(f.player.data(), config.data());
    config[0] = 1;
    items::queue(f.player.data(), nullptr, config.data(), 7, 1, 9, 10);
    require(isaac::runtime::pickupCalls == 2 && nativeQueues == 3,
            "Trinket, scripted grant or restored queue entered the pickup lottery");
    items::originalQueue = nullptr;
    isaac::runtime::divertPickup = false;
}
void* expectedProgress;
std::vector<int> progressWrites;
isaac::lan::Progress expectedLocalProgress;
void __attribute__((thiscall)) saveProgressCloudFixture(void* progress) {
    require(progress == expectedProgress, "Progress save used the wrong receiver");
    require(isaac::engine::session::readProgress() == expectedLocalProgress,
            "Saved shared values instead of merged local progress");
    progressWrites.push_back(1);
}
void __attribute__((thiscall)) saveProgressFileFixture(void* progress) {
    require(progress == expectedProgress && progressWrites == std::vector<int>{1},
            "Local progress save preceded the native cloud save");
    progressWrites.push_back(2);
}
void pendingRewardPersistence() {
    namespace session = isaac::engine::session;
    Fixture f;
    session::image = reinterpret_cast<Address>(f.image);
    *reinterpret_cast<Address*>(f.image + native::globals::manager) =
        reinterpret_cast<Address>(f.manager.data());
    expectedProgress = f.manager.data() + native::layout::manager::progress;
    auto publish = [&](unsigned entry, auto method) {
        auto call = f.image + entry;
        call[0] = 0xe9;
        const auto displacement = static_cast<unsigned>(reinterpret_cast<Address>(method) -
                                                        reinterpret_cast<Address>(call + 5));
        std::memcpy(call + 1, &displacement, 4);
    };
    publish(native::entry::progressSaveCloud, saveProgressCloudFixture);
    publish(native::entry::progressSaveFile, saveProgressFileFixture);
    require(FlushInstructionCache(GetCurrentProcess(), f.image, Fixture::size) != 0,
            "Cannot publish private progress save methods");
    constexpr unsigned pendingBlessings = 114;
    isaac::lan::Progress local, common, current;
    local.achievements[1] = 1;
    common.achievements[2] = 1;
    current = common;
    current.counters[pendingBlessings] = 1;
    expectedLocalProgress = isaac::lan::mergeProgress(local, common, current);
    session::writeProgress(expectedLocalProgress);
    progressWrites.clear();
    session::persistProgress();
    require(progressWrites == std::vector<int>({1, 2}), "Progress was not persisted");
    require(session::readProgress().counters[pendingBlessings] == 1 &&
                !session::readProgress().achievements[2],
            "Pending reward was lost or host achievements leaked");
    session::image = 0;
}
void startingRewards() {
    Fixture f;
    items::startingRewards(
        [&] {
            f.nativeReward(20);
            f.nativeReward(30);
            items::add(f.player.data(), nullptr, 40, -1, true, 0, 0, 0);
        },
        true);
    grants.clear();
    items::grantStartingRewards(f.player.data(), 0);
    require(grants.empty(), "The host's native rewards were replayed");
    items::grantStartingRewards(f.player.data(), 1);
    items::grantStartingRewards(f.player.data(), 1);
    require(grants == std::vector<int>({20, 30}), "Shared reward source or de-duplication failed");
    items::startingRewards([&] { f.nativeReward(50); }, false);
    grants.clear();
    items::grantStartingRewards(f.player.data(), 2);
    require(grants.empty(), "A solo start retained a LAN reward plan");
}
void beamDeparture() {
    Fixture f;
    // A native timer is adjacent player state, not owned by the beam adapter.
    constexpr unsigned duration = native::layout::player::megaBlastDuration;
    *reinterpret_cast<int*>(f.player.data() + duration) = 123;
    *reinterpret_cast<Address*>(f.player.data() + native::layout::player::megaBlastLaser) =
        reinterpret_cast<Address>(&f.beam);
    items::leaveRoom(f.player.data());
    items::leaveRoom(f.player.data());
    require(removals == 1 && detachments == 1, "Departure retained or removed a beam twice");
    require(*reinterpret_cast<int*>(f.player.data() + duration) == 123,
            "Departure restarted or consumed the remaining beam duration");
}
void* expectedGame;
bool blueRoomCreated;
unsigned blueRoomCalls;
bool __attribute__((thiscall)) blueRoomFixture(void* game, int source, int destination,
                                               int direction) {
    require(game == expectedGame && source == 84 && destination == 85 && direction == 2,
            "Blue room initialization changed its native receiver or arguments");
    ++blueRoomCalls;
    return blueRoomCreated;
}
void blueRoomEntry() {
    Fixture f;
    expectedGame = f.manager.data();
    auto call = f.image + native::entry::levelTryInitializeBlueRoom;
    call[0] = 0xe9;
    const auto displacement = static_cast<unsigned>(reinterpret_cast<Address>(blueRoomFixture) -
                                                    reinterpret_cast<Address>(call + 5));
    std::memcpy(call + 1, &displacement, 4);
    require(FlushInstructionCache(GetCurrentProcess(), f.image, Fixture::size) != 0,
            "Cannot publish the native blue room initializer");
    blueRoomCalls = 0;
    for (bool eligible : {false, true}) {
        blueRoomCreated = eligible;
        require(items::initializeBlueRoom(expectedGame, 84, 85, 2) == eligible,
                "Blue room adapter lost the native eligibility result");
    }
    require(blueRoomCalls == 2, "Blue room initialization was skipped or replayed");
}
unsigned revivalCalls;
void __attribute__((thiscall)) reviveCollectibleFixture(void* player, unsigned id, bool owned) {
    require(player == expectedPlayer && id == 619 && owned,
            "Collectible revival changed native arguments");
    require(isaac::rooms::revivalScoped == isaac::rooms::scopeAvailable,
            "Collectible revival escaped its actor scope");
    ++revivalCalls;
}
void __attribute__((thiscall)) reviveTrinketFixture(void* player, unsigned id, unsigned scratch) {
    require(player == expectedPlayer && id == 23 && scratch == 0x12345678,
            "Trinket revival changed native arguments or dropped J460's second stack word");
    require(isaac::rooms::revivalScoped == isaac::rooms::scopeAvailable,
            "Trinket revival escaped its actor scope");
    ++revivalCalls;
}
void revivalRoom() {
    Fixture f;
    *reinterpret_cast<unsigned*>(f.player.data() + native::layout::player::controller) = 2;
    items::originalReviveCollectible = reviveCollectibleFixture;
    items::originalReviveTrinket = reviveTrinketFixture;
    revivalCalls = 0;
    for (bool available : {true, false}) {
        isaac::rooms::scopeAvailable = available;
        items::reviveCollectible(f.player.data(), nullptr, 619, true);
        items::reviveTrinket(f.player.data(), nullptr, 23, 0x12345678);
    }
    require(revivalCalls == 4 && isaac::rooms::revivalSlot == 1 && !isaac::rooms::revivalScoped,
            "Revival was replayed, used another controller or retained its scope");
    items::originalReviveCollectible = nullptr;
    items::originalReviveTrinket = nullptr;
}
std::vector<void*> previewed;
Address previewRoom;
void __attribute__((thiscall)) previewFixture(void* pickup) {
    require(isaac::rooms::localPreviewRoster, "Preview escaped the local roster");
    previewed.push_back(pickup);
    // Creating a native ghost can replace the room's render array. The
    // adapter must finish the frozen pickup list without reading new storage.
    const auto list =
        previewRoom + native::layout::room::entities + native::layout::entityList::renderArray;
    *reinterpret_cast<Address*>(list + native::layout::entityList::data) = 0;
    *reinterpret_cast<unsigned*>(list + native::layout::entityList::count) = 0;
}
void localPickupPreview() {
    namespace preview = isaac::presentation::pickup_preview;
    namespace layout = native::layout;
    std::vector<unsigned char> image(native::globals::game + sizeof(Address));
    std::vector<unsigned char> game(layout::game::room + sizeof(Address));
    std::vector<unsigned char> room(layout::room::size);
    std::array<std::array<unsigned char, 0x400>, 5> entities{};
    std::array<Address, 5> rendered{};
    for (unsigned i = 0; i < entities.size(); ++i) {
        rendered[i] = reinterpret_cast<Address>(entities[i].data());
        *reinterpret_cast<unsigned*>(rendered[i] + layout::entity::type) =
            isaac::compat::ids::entity::pickup;
        *reinterpret_cast<bool*>(rendered[i] + layout::entity::active) = true;
    }
    *reinterpret_cast<bool*>(rendered[2] + layout::entity::registered) = true;
    *reinterpret_cast<bool*>(rendered[3] + layout::entity::active) = false;
    *reinterpret_cast<unsigned*>(rendered[4] + layout::entity::type) =
        isaac::compat::ids::entity::effect;
    previewRoom = reinterpret_cast<Address>(room.data());
    const auto list = previewRoom + layout::room::entities + layout::entityList::renderArray;
    *reinterpret_cast<Address*>(list + layout::entityList::data) =
        reinterpret_cast<Address>(rendered.data());
    *reinterpret_cast<unsigned*>(list + layout::entityList::count) = rendered.size();
    *reinterpret_cast<Address*>(game.data() + layout::game::room) = previewRoom;
    *reinterpret_cast<Address*>(image.data() + native::globals::game) =
        reinterpret_cast<Address>(game.data());
    preview::image = reinterpret_cast<Address>(image.data());
    preview::originalUpdate = previewFixture;
    previewed.clear();
    isaac::rooms::previewReady = false;
    preview::prepare();
    require(previewed.empty(), "Preview ran before its view was ready");
    isaac::rooms::previewReady = true;
    preview::prepare();
    require(previewed == std::vector<void*>({entities[0].data(), entities[1].data(),
                                             entities[2].data(), entities[3].data()}),
            "Preview missed rendered pickups or included non-pickup entities");
    preview::image = 0;
    preview::originalUpdate = nullptr;
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"collectible-pickup", collectiblePickup},
                     {"starting-rewards", startingRewards},
                     {"beam-departure", beamDeparture},
                     {"blue-room-entry", blueRoomEntry},
                     {"revival-room", revivalRoom},
                     {"pending-reward-persistence", pendingRewardPersistence},
                     {"local-pickup-preview", localPickupPreview}});
}

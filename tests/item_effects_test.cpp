// Private x86 image only: no game process, files, input or hooks are installed.
#include "test_support.h"
#include "engine/versions/j460/item_effects.cpp"
#include "engine/versions/j460/pickup_preview.cpp"
#include "engine/versions/j460/session_backend.cpp"
#include "runtime/progression.h"
#include <array>
#include <cstring>

namespace isaac::rooms {
bool previewReady = true, localPreviewRoster = false;
bool viewReady() {
    return previewReady;
}
bool virtualized() {
    return true;
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
                    {{"starting-rewards", startingRewards},
                     {"beam-departure", beamDeparture},
                     {"pending-reward-persistence", pendingRewardPersistence},
                     {"local-pickup-preview", localPickupPreview}});
}

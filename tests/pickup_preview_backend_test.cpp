#include "test_support.h"
#include "engine/pickup_preview.h"
#include "engine/rooms.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned roomOffset = 0x18190, existsOffset = 0x16a;
#else
#include "engine/versions/j511/entrypoints.h"
namespace backend = isaac::engine::j511;
constexpr unsigned roomOffset = 0x18300, existsOffset = 0x172;
#endif
#include <MinHook.h>
#include <array>
#include <cstring>
#include <vector>
namespace {
namespace preview = isaac::presentation::pickup_preview;
using Address = std::uintptr_t;
using Update = void(__attribute__((thiscall)) *)(void*);
constexpr unsigned imageSize = privateGameImageBytes, renderData = 0x125c, renderCount = 0x1264;
unsigned char* image;
std::array<unsigned char, 0x18400> game{};
std::array<std::array<unsigned char, 0x1300>, 2> roomObjects{};
std::array<std::array<unsigned char, 0x500>, 5> entities{};
std::array<Address, 6> renderList{};
std::vector<void*> updates;
unsigned currentView = 0, scopes = 0;
bool enabled = false, ready = false, localRoster = false, mutate = false, fail = false;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void roster(unsigned view, std::initializer_list<unsigned> indices) {
    unsigned count = 0;
    for (unsigned index : indices)
        renderList[count++] =
            index < entities.size() ? reinterpret_cast<Address>(entities[index].data()) : 0;
    field<Address>(roomObjects[view].data(), renderData) =
        reinterpret_cast<Address>(renderList.data());
    field<unsigned>(roomObjects[view].data(), renderCount) = count;
}
void __attribute__((thiscall)) nativeUpdate(void* object) {
    require(!enabled || localRoster, "Preview escaped its local player view");
    updates.push_back(object);
    if (mutate) {
        // Native ghost creation may replace the backing array. Poison old
        // storage; the frozen pickup list must still reach all original pickups.
        renderList.fill(0);
        field<Address>(roomObjects[currentView].data(), renderData) = 0;
        field<unsigned>(roomObjects[currentView].data(), renderCount) = 0;
    }
    if (fail)
        throw std::runtime_error("preview fixture failed");
}
void setup() {
    preview::prepare();
    require(!preview::install(0), "Missing image installed preview hooks");
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Allocate isolated preview fixture");
    auto* target = image + backend::entry::pickupUpdateGhosts;
    target[0] = 0xe9;
    const auto relative =
        reinterpret_cast<Address>(nativeUpdate) - reinterpret_cast<Address>(target + 5);
    std::memcpy(target + 1, &relative, 4);
    std::memset(target + 5, 0x90, 11);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(game.data(), roomOffset) = reinterpret_cast<Address>(roomObjects[0].data());
    for (auto& entity : entities) {
        field<unsigned>(entity.data(), 0x28) = 5;
        field<bool>(entity.data(), existsOffset) = true;
    }
    field<unsigned>(entities[2].data(), 0x28) = 1000;
    field<bool>(entities[3].data(), existsOffset) =
        false; // Native cleanup still needs this pickup.
    require(MH_CreateHook(target, reinterpret_cast<void*>(nativeUpdate), nullptr) == MH_OK,
            "Create foreign preview hook");
    require(!preview::install(reinterpret_cast<Address>(image)), "Foreign conflict was ignored");
    require(MH_CreateHook(target, reinterpret_cast<void*>(nativeUpdate), nullptr) ==
                MH_ERROR_ALREADY_CREATED,
            "Failed installation removed a foreign hook");
    require(MH_RemoveHook(target) == MH_OK && preview::install(reinterpret_cast<Address>(image)),
            "Preview installation could not retry");
    require(!preview::install(reinterpret_cast<Address>(image)),
            "Duplicate preview installation succeeded");
}
void check() {
    const auto update = reinterpret_cast<Update>(image + backend::entry::pickupUpdateGhosts);
    update(entities[0].data());
    require(updates.size() == 1, "Single player lost native preview update");
    enabled = true;
    update(entities[1].data());
    require(updates.size() == 1, "LAN gameplay scope updated another player's preview");
    updates.clear();
    roster(0, {0, 1, 2, 3, 5});
    preview::prepare();
    require(updates.empty() && scopes == 0, "Unready view entered native preview update");
    ready = true;
    mutate = true;
    preview::prepare();
    require(updates == std::vector<void*>(
                           {entities[0].data(), entities[1].data(), entities[3].data()}) &&
                scopes == 1 && !localRoster,
            "Render list mutation lost pickups, native cleanup, or scope restoration");
    const auto initial = updates.size();
    preview::prepare();
    require(updates.size() == initial, "Empty list retained borrowed pickup pointers");
    // A new local room is borrowed only inside withView and restored afterwards.
    currentView = 1;
    roster(1, {4});
    preview::prepare();
    require(updates.size() == initial + 1 && updates.back() == entities[4].data() &&
                field<Address>(game.data(), roomOffset) ==
                    reinterpret_cast<Address>(roomObjects[0].data()),
            "Room switch retained prior previews or native room pointer");
    roster(1, {1});
    fail = true;
    rejects([] { preview::prepare(); }, "Preview failure was not surfaced");
    require(!localRoster && field<Address>(game.data(), roomOffset) ==
                                reinterpret_cast<Address>(roomObjects[0].data()),
            "Failed preview leaked local view");
    fail = false;
    roster(1, {4});
    preview::prepare();
    require(updates.back() == entities[4].data(), "Preview retained stale pointers after failure");
    enabled = false;
    ready = false;
    const auto before = updates.size();
    preview::prepare();
    update(entities[0].data());
    require(updates.size() == before + 1 && !localRoster,
            "Leaving LAN did not restore native preview behavior");
    enabled = true;
    ready = true;
    currentView = 0;
    roster(0, {1});
    preview::prepare();
    require(updates.back() == entities[1].data(), "Rejoining reused previous local preview");
}
} // namespace
namespace isaac::rooms {
bool virtualized() {
    return enabled;
}
bool viewReady() {
    return ready;
}
void withView(const std::function<void()>& call, bool localPlayersOnly) {
    require(localPlayersOnly && !localRoster,
            "Preview requested a full roster or reentered itself");
    auto& pointer = field<Address>(game.data(), roomOffset);
    struct Restore {
        Address& pointer;
        Address previous;
        ~Restore() {
            pointer = previous;
            localRoster = false;
        }
    } restore{pointer, pointer};
    pointer = reinterpret_cast<Address>(roomObjects[currentView].data());
    localRoster = true;
    ++scopes;
    call();
}
} // namespace isaac::rooms
int main() {
    try {
        setup();
        check();
        require(MH_Uninitialize() == MH_OK, "Remove preview fixture hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS pickup preview ABI, local room, render-array mutation and cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

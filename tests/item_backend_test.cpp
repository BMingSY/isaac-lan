#include "test_support.h"
#include "engine/versions/common/item_effects.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#else
#include "engine/versions/j460/entrypoints.h"
#endif
#include <vector>

struct lua_State {
    std::array<long long, 6> args{};
    std::vector<long long> results;
    std::string text;
};
namespace {
namespace items = isaac::engine::items;
#ifdef ISAAC_LAN_TEST_J835
namespace backend = isaac::engine::j835;
constexpr unsigned spriteOffset = 0x3c, seedOffset = 0x344, activeOffset = 0x16a;
constexpr unsigned controllerOffset = 0x154c, activeItemOffset = 0x14c4, activeStride = 0x1c;
constexpr unsigned playersOffset = 0x1ba50, beamOffset = 0x13a0, durationOffset = 0x1814;
constexpr unsigned chargeOffset = 0x474, dataOffset = 0x4e8, stringTableOffset = 0x4a234;
constexpr int forwardedPool = 0;
#else
namespace backend = isaac::engine::j460;
constexpr unsigned spriteOffset = 0x48, seedOffset = 0x3ec, activeOffset = 0x172;
constexpr unsigned controllerOffset = 0x1618, activeItemOffset = 0x1580, activeStride = 0x20;
constexpr unsigned playersOffset = 0x1baa8, beamOffset = 0x1458, durationOffset = 0x18f4;
constexpr unsigned chargeOffset = 0x524, dataOffset = 0x59c, stringTableOffset = 0x4a920;
constexpr unsigned poolOffset = 0x530;
constexpr int forwardedPool = 10;
#endif
using Address = std::uintptr_t;
unsigned char* image;
constexpr unsigned imageSize = 0x890000;
std::vector<unsigned char> game(0x1bb00), manager(0x4ac00);
std::array<unsigned char, 0x2300> player{};
std::array<unsigned char, 0x600> pickup{}, beam{};
std::array<unsigned char, 0x100> config{};
std::array<unsigned char, 8> configManager{};
std::array<Address, 11> entityVtable{};
std::array<Address, 1> roster{};
std::array<Address, 2> sprite{};
unsigned scopeSlot = 0, queued = 0, intercepted = 0, removes = 0, detaches = 0;
unsigned revivals = 0, chargeCalls = 0;
bool scoped = false, scopeAvailable = true, divert = true, replica = false, view = true;
std::size_t wrapperSize = 8;
struct Grant {
    int item, charge;
    bool first;
    int slot, data, pool;
};
std::vector<Grant> grants;
std::vector<bool> drops;
template <class T> T& field(void* p, unsigned offset = 0) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(p) + offset);
}
Address base() {
    return reinterpret_cast<Address>(image);
}
void checkPlayer(void* object) {
    require(object == player.data(), "Native item receiver");
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
bool takeCollectiblePickup(int owner, unsigned seed, int id, int charge, bool touched, int data,
                           int pool) {
    require(owner == 1 && seed == 123 && id == 12 && charge == 7 && touched && data == 9 &&
                pool == forwardedPool,
            "Pickup forwarding lost native metadata or invented a pool");
    ++intercepted;
    return divert;
}
} // namespace isaac::runtime
namespace isaac::rooms {
bool virtualized() {
    return true;
}
bool viewReady() {
    return view;
}
unsigned connected() {
    return 3;
}
bool withPlayer(unsigned slot, const std::function<void()>& run) {
    if (!scopeAvailable)
        return false;
    scopeSlot = slot;
    scoped = true;
    run();
    scoped = false;
    return true;
}
} // namespace isaac::rooms
namespace {
#ifdef ISAAC_LAN_TEST_J835
void __attribute__((thiscall)) add(void* object, int id, int charge, bool first, int slot,
                                   int data) {
    const int pool = 0;
#else
void __attribute__((thiscall)) add(void* object, int id, int charge, bool first, int slot, int data,
                                   int pool) {
#endif
    checkPlayer(object);
    grants.push_back({id, charge, first, slot, data, pool});
}
#ifdef ISAAC_LAN_TEST_J835
void __attribute__((thiscall)) queue(void* object, void* item, int charge, unsigned char flags,
                                     int data) {
    const int pool = 0;
#else
void __attribute__((thiscall)) queue(void* object, void* item, int charge, unsigned char flags,
                                     int data, int pool) {
#endif
    checkPlayer(object);
    require(item == config.data() && charge == 7 && flags == 0x81 && data == 9 &&
                pool == forwardedPool,
            "Queue ABI parameter or stack cleanup changed");
    ++queued;
}
void __attribute__((thiscall)) reviveCollectible(void* object, unsigned id, bool owned) {
    checkPlayer(object);
    require(id == 11 && owned && scoped == scopeAvailable && (!scoped || scopeSlot == 1),
            "Collectible revival lost the actor's room or ABI flags");
    ++revivals;
}
void __attribute__((thiscall)) reviveTrinket(void* object, unsigned id, unsigned scratch) {
    checkPlayer(object);
    require(id == 22 && scratch == 0xdecafbad && scoped == scopeAvailable &&
                (!scoped || scopeSlot == 1),
            "Trinket revival did not preserve both native stack words");
    ++revivals;
}
void* __cdecl getConfig() {
    return configManager.data();
}
Address __attribute__((thiscall)) getItem(void* receiver, int id) {
    require(receiver == configManager.data(), "ItemConfig receiver");
    return id == 12 ? reinterpret_cast<Address>(config.data()) : 0;
}
bool __attribute__((thiscall)) has(void* object, int id, bool ignore) {
    checkPlayer(object);
    require(id == 12 && ignore, "HasCollectible ABI");
    return true;
}
Address __attribute__((thiscall)) drop(void* object, int id, void* existing, bool removeFromForm) {
    checkPlayer(object);
    require((id == 12 || id == 44) && !existing, "DropCollectible ABI");
    drops.push_back(removeFromForm);
    return reinterpret_cast<Address>(pickup.data());
}
void __attribute__((thiscall)) remove(void* object) {
    require(object == pickup.data() || object == beam.data(), "Removal used an unowned entity");
    ++removes;
}
void __attribute__((fastcall)) detach(void* reference, void* target) {
    require(reference == player.data() + beamOffset && !target && removes == detaches + 2,
            "Laser must be removed before its native reference is detached");
    field<Address>(reference) = 0;
    ++detaches;
}
int __attribute__((thiscall)) maxCharge(void* object, int slot) {
    checkPlayer(object);
    require(slot == 2, "Native max-charge slot");
    return 6;
}
#ifndef ISAAC_LAN_TEST_J835
int __attribute__((thiscall)) chargeType(void* object, int slot) {
    checkPlayer(object);
    require(slot == 2, "Plus charge-type slot");
    return field<int>(config.data(), 0xac);
}
#endif
int __attribute__((thiscall)) addCharge(void* object, int amount, int slot, bool flash,
                                        bool overcharge, bool force) {
    checkPlayer(object);
    require(amount == 3 && slot == 2 && !flash && !overcharge && !force,
            "AddActiveCharge ABI/flags");
    ++chargeCalls;
    return 2;
}
bool __attribute__((thiscall)) blueRoom(void* object, int from, int to, int direction) {
    require(object == game.data() && from == 84 && to == 85 && direction == 2,
            "Blue room native ABI");
    return true;
}
const char* __attribute__((thiscall)) lookup(void* object, const char* table, int language,
                                             const char* key, bool* missing) {
    require(object == manager.data() + stringTableOffset && !std::strcmp(table, "Items") &&
                !std::strcmp(key, "item") && language == 3,
            "Translation receiver or key");
    *missing = false;
    return "Native item";
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    field<std::uint32_t>(image, rva + 1) =
        static_cast<std::uint32_t>(reinterpret_cast<Address>(fn) - base() - rva - 5);
    std::memset(image + rva + 5, 0x90, 11);
}
Address callsite(unsigned returned, unsigned target, bool reward) {
    // Thiscall wrapper accepts item/config and synthesizes only this version's
    // native arguments; an incorrect RET size corrupts the caller's stack.
    std::vector<unsigned char> setup{0x8b, 0x44, 0x24, 4};
#ifndef ISAAC_LAN_TEST_J835
    setup.insert(setup.end(), {0x6a, static_cast<unsigned char>(reward ? 0 : 10)});
#endif
    if (reward)
        setup.insert(setup.end(), {0x6a, 0, 0x6a, 0, 0x6a, 1, 0x6a, 0xff, 0x50});
    else
        setup.insert(setup.end(), {0x6a, 9, 0x68, 0x81, 0, 0, 0, 0x6a, 7, 0x50});
    auto* call = image + returned - 5;
    std::memcpy(call - setup.size(), setup.data(), setup.size());
    call[0] = 0xe8;
    field<std::uint32_t>(call, 1) = target - returned;
    call[5] = 0xc2;
    call[6] = 4;
    call[7] = 0;
    return reinterpret_cast<Address>(call - setup.size());
}
Address grantSite, pickupSite;
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Prepare native item fixture");
    patch(backend::entry::playerAddCollectible, add);
    patch(backend::entry::playerQueueItem, queue);
    patch(backend::entry::playerReviveCollectible, reviveCollectible);
    patch(backend::entry::playerReviveTrinket, reviveTrinket);
    patch(backend::entry::managerGetItemConfig, getConfig);
    patch(backend::entry::itemConfigGetCollectible, getItem);
    patch(backend::entry::playerHasCollectible, has);
    patch(backend::entry::playerDropCollectible, drop);
    patch(backend::entry::playerActiveMaxCharge, maxCharge);
    patch(backend::entry::playerAddActiveCharge, addCharge);
    patch(backend::entry::levelTryInitializeBlueRoom, blueRoom);
    patch(backend::entry::entityPtrAssign, detach);
    patch(backend::entry::stringTableLookup, lookup);
#ifndef ISAAC_LAN_TEST_J835
    patch(backend::entry::playerActiveChargeType, chargeType);
#endif
    grantSite =
        callsite(backend::entry::edensBlessingGranted, backend::entry::playerAddCollectible, true);
    pickupSite =
        callsite(backend::entry::pickupQueuedCollectible, backend::entry::playerQueueItem, false);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    field<Address>(image, backend::globals::manager) = reinterpret_cast<Address>(manager.data());
    roster[0] = reinterpret_cast<Address>(player.data());
    field<Address>(game.data(), playersOffset) = reinterpret_cast<Address>(roster.data());
    field<Address>(game.data(), playersOffset + 4) = reinterpret_cast<Address>(roster.data() + 1);
    field<int>(player.data(), controllerOffset) = 2;
    field<unsigned>(player.data(), seedOffset) = 123;
    field<unsigned>(player.data(), 0x28) = 1;
    field<bool>(player.data(), activeOffset) = true;
    sprite = {0, reinterpret_cast<Address>(player.data()) + spriteOffset};
    field<int>(config.data()) = 1;
    field<int>(config.data(), 4) = 12;
    std::memcpy(config.data() + 8, "#item", 6);
    field<unsigned>(config.data(), 8 + 0x10) = 5;
    field<unsigned>(config.data(), 8 + 0x14) = 15;
    field<int>(manager.data(), stringTableOffset) = 3;
    field<int>(pickup.data(), chargeOffset) = 7;
    field<int>(pickup.data(), dataOffset) = 9;
#ifndef ISAAC_LAN_TEST_J835
    field<int>(pickup.data(), poolOffset) = 10;
#else
    field<unsigned>(pickup.data(), 0x480) = 0xfedcba98; // Original price, not a source pool.
#endif
    entityVtable[0x28 / 4] = reinterpret_cast<Address>(remove);
    field<Address>(pickup.data()) = field<Address>(beam.data()) =
        reinterpret_cast<Address>(entityVtable.data());
    items::lua.rawLength = [](lua_State*, int) { return wrapperSize; };
    items::lua.toUserdata = [](lua_State*, int) -> void* { return sprite.data(); };
    items::lua.checkInteger = [](lua_State* L, int i) { return L->args[i - 1]; };
    items::lua.toBoolean = [](lua_State* L, int i) { return int(L->args[i - 1] != 0); };
    items::lua.pushInteger = [](lua_State* L, long long n) { L->results.push_back(n); };
    items::lua.pushBoolean = [](lua_State* L, int n) { L->results.push_back(n != 0); };
    items::lua.pushString = [](lua_State* L, const char* s) {
        L->text = s;
        return L->text.c_str();
    };
    auto* foreign = image + backend::entry::playerReviveTrinket;
    require(MH_CreateHook(foreign, reinterpret_cast<void*>(reviveTrinket), nullptr) == MH_OK,
            "Install foreign conflict");
    require(!items::install(base()), "Incomplete item hook group must fail");
    require(MH_CreateHook(image + backend::entry::playerAddCollectible,
                          reinterpret_cast<void*>(add), nullptr) == MH_OK,
            "Failed item installation leaked its earlier hook");
    require(MH_RemoveHook(image + backend::entry::playerAddCollectible) == MH_OK &&
                MH_RemoveHook(foreign) == MH_OK,
            "Rollback removed a foreign hook");
    require(items::install(base()) && !items::install(base()),
            "Item hook retry/duplicate contract");
}
void rewardAndPickup() {
    using GrantCall = void(__attribute__((thiscall))*)(void*, int);
    const auto nativeReward = reinterpret_cast<GrantCall>(grantSite);
    items::startingRewards(
        [&] {
            nativeReward(player.data(), 12);
            items::originalAdd(player.data(), 99, -1, true, 0, 0, 0);
        },
        true);
    grants.clear();
    items::grantStartingRewards(player.data(), 1);
    items::grantStartingRewards(player.data(), 1);
    items::grantStartingRewards(player.data(), 0);
    require(grants.size() == 1 && grants[0].item == 12 && grants[0].charge == -1 &&
                grants[0].first && grants[0].slot == 0 && grants[0].data == 0 &&
                grants[0].pool == 0,
            "Blessing replication changed native argument count or copied another grant");
    items::startingRewards([] {}, false);
    items::grantStartingRewards(player.data(), 2);
    require(grants.size() == 1, "A new session inherited old starting rewards");
    try {
        items::startingRewards(
            [&] {
                nativeReward(player.data(), 12);
                throw 1;
            },
            true);
    } catch (int) {
    }
    grants.clear();
    items::grantStartingRewards(player.data(), 2);
    require(grants.empty(), "Failed native start retained partial starting rewards");
    using PickupCall = void(__attribute__((thiscall))*)(void*, void*);
    const auto acquire = reinterpret_cast<PickupCall>(pickupSite);
    acquire(player.data(), config.data());
    require(intercepted == 1 && queued == 0, "Diverted pickup was also queued natively");
    divert = false;
    acquire(player.data(), config.data());
    require(intercepted == 2 && queued == 1, "Rejected diversion suppressed the native queue");
    field<int>(config.data()) = 2;
    acquire(player.data(), config.data());
    items::originalQueue(player.data(), config.data(), 7, 0x81, 9, forwardedPool);
    require(intercepted == 2 && queued == 3,
            "Trinkets or restored queues entered pickup diversion");
    field<int>(config.data()) = 1;
}
void inventoryAndCharge() {
    lua_State state;
    state.args[1] = 12;
    require(items::take(&state) == 3 &&
                state.results == std::vector<long long>({7, 9, forwardedPool}) && removes == 1 &&
                drops == std::vector<bool>{true},
            "Take must copy native metadata before removal");
    state.results.clear();
    state.args = {0, 12, 7, 1, 9, 10};
    field<int>(config.data()) = 3;
    field<int>(player.data(), activeItemOffset) = 44;
    const auto before = pickup;
    require(items::give(&state) == 1 && state.results == std::vector<long long>{1} &&
                drops == std::vector<bool>({true, false}),
            "Giving an active item must preserve native drop semantics");
    const auto& grant = grants.back();
    require(grant.item == 12 && grant.charge == 7 && grant.first && grant.slot == 0 &&
                grant.data == 9 && grant.pool == forwardedPool && pickup == before,
            "Grant metadata or original pool omission changed");
    field<int>(player.data(), activeItemOffset + 2 * activeStride) = 12;
    field<int>(config.data(), 0xac) = 1;
    state.args = {0, 2, 3};
    state.results.clear();
    require(items::activeCharge(&state) == 2 && state.results == std::vector<long long>({1, 6}),
            "Active charge-type/capacity query");
    state.results.clear();
    require(items::addActiveCharge(&state) == 1 && state.results == std::vector<long long>{2} &&
                chargeCalls == 1,
            "Charge must be applied once through native capacity/overflow logic");
    for (auto invalid : {-1, 4}) {
        state.args[1] = invalid;
        require(items::activeCharge(&state) == 0 && items::addActiveCharge(&state) == 0,
                "Invalid slot reached native charge");
    }
    state.args[1] = 2;
    replica = true;
    require(items::activeCharge(&state) == 0, "Replica modified native item state");
    replica = false;
    wrapperSize = 16;
    require(items::addActiveCharge(&state) == 0 && chargeCalls == 1,
            "Unowned wrapper reached native charge");
    wrapperSize = 8;
    state.args[0] = 12;
    require(items::name(&state) == 1 && state.text == "Native item",
            "Version-specific string-table lookup");
}
void roomLifetimes() {
    using Collectible = void(__attribute__((thiscall))*)(void*, unsigned, bool);
    using Trinket = void(__attribute__((thiscall))*)(void*, unsigned, unsigned);
    for (bool available : {true, false}) {
        scopeAvailable = available;
        reinterpret_cast<Collectible>(image + backend::entry::playerReviveCollectible)(
            player.data(), 11, true);
        reinterpret_cast<Trinket>(image + backend::entry::playerReviveTrinket)(player.data(), 22,
                                                                               0xdecafbad);
    }
    require(revivals == 4 && !scoped, "Revival was duplicated or retained a borrowed room scope");
    require(items::initializeBlueRoom(game.data(), 84, 85, 2), "Blue-room native initializer");
    field<Address>(player.data(), beamOffset) = reinterpret_cast<Address>(beam.data());
    field<int>(player.data(), durationOffset) = 91;
    items::leaveRoom(player.data());
    items::leaveRoom(player.data());
    require(detaches == 1 && removes == 2 && field<int>(player.data(), durationOffset) == 91,
            "Repeated room exit reused an old laser or cleared remaining item duration");
}
} // namespace
int main() {
    setup();
    rewardAndPickup();
    inventoryAndCharge();
    roomLifetimes();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release item fixture");
}

namespace isaac::presentation::moving_box {
bool capture(std::uintptr_t) {
    return false;
}
void apply(std::uintptr_t, bool) {}
} // namespace isaac::presentation::moving_box
namespace isaac::runtime {
void abort(const std::string& reason) {
    throw std::runtime_error(reason);
}
} // namespace isaac::runtime
namespace isaac::engine::native_certificate_return {
bool install(std::uintptr_t) {
    return true;
}
} // namespace isaac::engine::native_certificate_return
#ifndef ISAAC_LAN_TEST_J835
namespace isaac::engine::j460 {
namespace cursed_mist {
bool install(std::uintptr_t) {
    return true;
}
} // namespace cursed_mist
} // namespace isaac::engine::j460
#endif

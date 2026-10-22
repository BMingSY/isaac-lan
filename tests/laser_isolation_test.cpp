// Exercise the persistent laser hook's enrollment and role transitions.
#include <MinHook.h>
MH_STATUS WINAPI testCreateHook(void*, void*, void**);
MH_STATUS WINAPI testEnableHook(void*);
MH_STATUS WINAPI testDisableHook(void*);
MH_STATUS WINAPI testRemoveHook(void*);
#define MH_CreateHook testCreateHook
#define MH_EnableHook testEnableHook
#define MH_DisableHook testDisableHook
#define MH_RemoveHook testRemoveHook
#include "engine/versions/j460/laser_links.cpp"
#include "runtime/session.h"
#include "test_support.h"
#include <array>
#include <map>

namespace {
namespace links = isaac::engine::j460::laser_links;
using Address = std::uintptr_t;
struct Hook {
    void* callback;
    bool enabled = false;
};
std::map<void*, Hook> hooks;
bool guest = false, failCreate = false, failEnable = false;
unsigned creates = 0, removes = 0, updates = 0, setters = 0;
constexpr Address imageBase = 0x10000000;
constexpr Address laserEntry = imageBase + isaac::engine::j460::entry::laserUpdate;
void*& parent(void* value) {
    return *reinterpret_cast<void**>(static_cast<char*>(value) +
                                     isaac::engine::j460::layout::laser::parent);
}
void __attribute__((thiscall)) update(void* value) {
    require(parent(value) != value, "Original Update received an uncleared self-cycle");
    ++updates;
}
void __attribute__((thiscall)) clear(void* value, void* next) {
    require(next == nullptr, "Replica handoff assigned an unrelated parent");
    parent(value) = nullptr;
    ++setters;
}
void reset() {
    hooks.clear();
    guest = failCreate = failEnable = false;
    creates = removes = updates = setters = 0;
    links::installedUpdate = 0;
    links::resetReplicaIsolation();
}
void installation() {
    reset();
    require(!links::interceptReplicaUpdate(laserEntry), "Uninstalled entry claimed isolation");
    require(!links::install(imageBase, nullptr), "Missing replica predicate was accepted");
    failCreate = true;
    require(!links::install(imageBase, isaac::runtime::replica) &&
                !links::interceptReplicaUpdate(laserEntry),
            "Failed hook creation claimed isolation");
    failCreate = false;
    failEnable = true;
    require(!links::install(imageBase, isaac::runtime::replica) &&
                !links::interceptReplicaUpdate(laserEntry),
            "Disabled hook claimed isolation");
}
void lifecycle() {
    reset();
    require(links::install(imageBase, isaac::runtime::replica), "Laser install failed");
    require(!links::interceptReplicaUpdate(laserEntry + 1), "Unrelated entry claimed isolation");
    require(reinterpret_cast<Address>(links::nativeSetParent) ==
                imageBase + isaac::engine::j460::entry::laserSetParent,
            "Install resolved a different native setter");
    links::nativeSetParent = clear;
    std::array<Address, 0x540 / 4> laser{};
    const auto callLaser = [&](void* value) {
        using Callback = void(__attribute__((fastcall))*)(void*, void*);
        reinterpret_cast<Callback>(hooks.at(reinterpret_cast<void*>(laserEntry)).callback)(value,
                                                                                           nullptr);
    };
    guest = true;
    parent(laser.data()) = laser.data();
    callLaser(laser.data());
    require(setters == 1 && updates == 1, "Guest loading before enrollment was suppressed");
    for (unsigned round = 0; round < 2; ++round) {
        require(links::interceptReplicaUpdate(laserEntry) &&
                    links::interceptReplicaUpdate(laserEntry),
                "Installed laser entry did not claim isolation");
        require(creates == 1 && hooks.size() == 1, "Enrollment reinstalled the laser hook");
        const auto beforeUpdates = updates, beforeSetters = setters;
        parent(laser.data()) = laser.data();
        callLaser(nullptr);
        callLaser(laser.data());
        require(updates == beforeUpdates && setters == beforeSetters &&
                    parent(laser.data()) == laser.data(),
                "Enrolled guest read or modified native laser gameplay");
        guest = false;
        callLaser(laser.data());
        require(updates == beforeUpdates + 1 && setters == beforeSetters + 1,
                "Host or solo role retained guest isolation");
        guest = true;
        links::resetReplicaIsolation();
        require(hooks.size() == 1 && hooks.at(reinterpret_cast<void*>(laserEntry)).enabled &&
                    removes == 0,
                "Isolation cleanup removed the persistent laser hook");
        parent(laser.data()) = laser.data();
        callLaser(laser.data());
        require(updates == beforeUpdates + 2 && setters == beforeSetters + 2,
                "Cleanup retained guest isolation before the next enrollment");
    }
}
} // namespace

namespace isaac::runtime {
bool replica() {
    return guest;
}
void abort(const std::string& message) {
    throw std::runtime_error(message);
}
} // namespace isaac::runtime

MH_STATUS WINAPI testCreateHook(void* target, void* callback, void** original) {
    ++creates;
    if (failCreate)
        return MH_ERROR_UNSUPPORTED_FUNCTION;
    if (hooks.contains(target))
        return MH_ERROR_ALREADY_CREATED;
    hooks.emplace(target, Hook{callback});
    *original = reinterpret_cast<void*>(update);
    return MH_OK;
}
MH_STATUS WINAPI testEnableHook(void* target) {
    if (failEnable)
        return MH_ERROR_MEMORY_PROTECT;
    hooks.at(target).enabled = true;
    return MH_OK;
}
MH_STATUS WINAPI testDisableHook(void* target) {
    hooks.at(target).enabled = false;
    return MH_OK;
}
MH_STATUS WINAPI testRemoveHook(void* target) {
    ++removes;
    require(hooks.erase(target) == 1, "Removed an unowned hook");
    return MH_OK;
}
int main(int argc, char** argv) {
    static_assert(sizeof(void*) == 4);
    return runTests(argc, argv, {{"installation", installation}, {"lifecycle", lifecycle}});
}

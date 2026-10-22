#include "engine/versions/j460/laser_links.h"
#include "engine/versions/j460/entrypoints.h"
#include <MinHook.h>

namespace isaac::engine::j460::laser_links {
namespace {
SetParent nativeSetParent = nullptr;
Update originalUpdate = nullptr;
bool (*isReplica)() = nullptr;
std::uintptr_t installedUpdate = 0;
bool replicaIsolationActive = false;
void __attribute__((fastcall)) updateLaser(void* laser, void*) {
    if (replicaIsolationActive && isReplica())
        return;
    // Native callers also assign parent references inline before Update.
    // Clear a cyclic chain through the setter's EntityPtr observer cleanup.
    update(laser, nativeSetParent, originalUpdate);
}
} // namespace
bool install(std::uintptr_t image, bool (*replica)()) {
    if (!replica)
        return false;
    isReplica = replica;
    nativeSetParent = reinterpret_cast<SetParent>(image + entry::laserSetParent);
    auto* target = reinterpret_cast<void*>(image + entry::laserUpdate);
    if (MH_CreateHook(target, reinterpret_cast<void*>(updateLaser),
                      reinterpret_cast<void**>(&originalUpdate)) != MH_OK ||
        MH_EnableHook(target) != MH_OK)
        return false;
    installedUpdate = reinterpret_cast<std::uintptr_t>(target);
    return true;
}
bool interceptReplicaUpdate(std::uintptr_t entry) {
    if (!installedUpdate || entry != installedUpdate)
        return false;
    replicaIsolationActive = true;
    return true;
}
void resetReplicaIsolation() {
    replicaIsolationActive = false;
}
} // namespace isaac::engine::j460::laser_links

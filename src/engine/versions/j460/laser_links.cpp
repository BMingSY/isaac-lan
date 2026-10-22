#include "engine/versions/j460/laser_links.h"
#include "engine/versions/j460/entrypoints.h"
#include <MinHook.h>

namespace isaac::engine::j460::laser_links {
namespace {
SetParent nativeSetParent = nullptr;
Update originalUpdate = nullptr;
void __attribute__((fastcall)) updateLaser(void* laser, void*) {
    // Native callers also assign parent references inline before Update.
    // Clear a cyclic chain through the setter's EntityPtr observer cleanup.
    update(laser, nativeSetParent, originalUpdate);
}
} // namespace
bool install(std::uintptr_t image) {
    nativeSetParent = reinterpret_cast<SetParent>(image + entry::laserSetParent);
    auto* target = reinterpret_cast<void*>(image + entry::laserUpdate);
    return MH_CreateHook(target, reinterpret_cast<void*>(updateLaser),
                         reinterpret_cast<void**>(&originalUpdate)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
} // namespace isaac::engine::j460::laser_links

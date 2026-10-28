#include "engine/versions/common/input_bindings.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <MinHook.h>

namespace isaac::engine::native_input {
namespace {
using Address = std::uintptr_t;
template <class T> T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<T*>(address + offset);
}
bool installQuery(Address image, Detour detour, Query& original,
                  void (*logger)(const std::string&)) {
    if (!image || !detour || original)
        return false;
    const auto vtable = at<Address>(image, j460::globals::inputManager);
    if (!vtable)
        return false;
    const auto target =
        reinterpret_cast<void*>(at<Address>(vtable, j460::layout::inputManager::queryMethod));
    if (logger)
        logger("input_query_rva=" + std::to_string(reinterpret_cast<Address>(target) - image));
    if (MH_CreateHook(target, reinterpret_cast<void*>(detour),
                      reinterpret_cast<void**>(&original)) != MH_OK)
        return false;
    if (MH_EnableHook(target) == MH_OK)
        return true;
    MH_RemoveHook(target);
    original = nullptr;
    return false;
}
native_mouse::Router mouseRouter;
native_mouse::Aim originalMouse;
bool __attribute__((fastcall)) mouse(void* player, void*, native_mouse::Vector* result, bool raw) {
    const auto routed = mouseRouter(player, result);
    return routed == native_mouse::Result::passthrough ? originalMouse(player, result, raw)
                                                       : routed == native_mouse::Result::active;
}
bool installMouse(Address image, native_mouse::Router router, native_mouse::Aim& original) {
    if (!image || !router || originalMouse)
        return false;
    const auto target = reinterpret_cast<void*>(image + j460::entry::playerMouseAim);
    if (MH_CreateHook(target, reinterpret_cast<void*>(mouse),
                      reinterpret_cast<void**>(&originalMouse)) != MH_OK)
        return false;
    mouseRouter = router;
    if (MH_EnableHook(target) == MH_OK) {
        original = originalMouse;
        return true;
    }
    MH_RemoveHook(target);
    mouseRouter = nullptr;
    originalMouse = nullptr;
    return false;
}
int nativeAction(int action) {
    return action;
}
void resetMenuPrompts(Address image) {
    if (!image)
        return;
    const auto manager = at<Address>(image, j460::globals::manager);
    if (!manager)
        return;
    // J460 keeps its button-prompt group in Manager after menu destruction.
    using Reset = void(__attribute__((thiscall))*)(void*, bool);
    reinterpret_cast<Reset>(image + j460::entry::managerResetButtonPrompts)(
        reinterpret_cast<void*>(manager + j460::layout::manager::buttonPrompts), false);
}
} // namespace
const Bindings bindings{j460::globals::game,
                        j460::globals::manager,
                        j460::globals::inputManager,
                        j460::entry::inputPressed,
                        j460::entry::inputTriggered,
                        j460::entry::inputValue,
                        j460::entry::playerShootingEntity,
                        j460::layout::manager::renderFrame,
                        j460::layout::game::pauseMenu,
                        j460::layout::game::players,
                        {j460::layout::player::controller, j460::layout::entity::positionX,
                         j460::layout::entity::positionY},
                        installQuery,
                        installMouse,
                        nativeAction,
                        resetMenuPrompts};
} // namespace isaac::engine::native_input

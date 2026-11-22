#include "engine/versions/common/input_bindings.h"
#include "engine/versions/repentance_plus/entrypoints.h"
#include "engine/versions/repentance_plus/layout.h"
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
    const auto vtable = at<Address>(image, repentance_plus::globals::inputManager);
    if (!vtable)
        return false;
    const auto target = reinterpret_cast<void*>(
        at<Address>(vtable, repentance_plus::layout::inputManager::queryMethod));
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
    const auto target = reinterpret_cast<void*>(image + repentance_plus::entry::playerMouseAim);
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
    const auto manager = at<Address>(image, repentance_plus::globals::manager);
    if (!manager)
        return;
    // Repentance+ keeps its button-prompt group in Manager after menu destruction.
    using Reset = void(__attribute__((thiscall))*)(void*, bool);
    reinterpret_cast<Reset>(image + repentance_plus::entry::managerResetButtonPrompts)(
        reinterpret_cast<void*>(manager + repentance_plus::layout::manager::buttonPrompts), false);
}
} // namespace
const Bindings bindings{repentance_plus::globals::game,
                        repentance_plus::globals::manager,
                        repentance_plus::globals::inputManager,
                        repentance_plus::entry::inputPressed,
                        repentance_plus::entry::inputTriggered,
                        repentance_plus::entry::inputValue,
                        repentance_plus::entry::playerShootingEntity,
                        repentance_plus::layout::manager::renderFrame,
                        repentance_plus::layout::game::pauseMenu,
                        repentance_plus::layout::game::players,
                        repentance_plus::layout::inputDevice::keyboardId,
                        repentance_plus::layout::inputDevice::firstGamepadId,
                        {repentance_plus::layout::player::controller,
                         repentance_plus::layout::entity::positionX,
                         repentance_plus::layout::entity::positionY},
                        installQuery,
                        installMouse,
                        nativeAction,
                        resetMenuPrompts};
} // namespace isaac::engine::native_input

#include "engine/versions/j835/input_queries.h"
#include "engine/versions/j835/entrypoints.h"
#include <MinHook.h>
#include <array>

namespace isaac::engine::j835::input_queries {
namespace {
using Button = bool(__attribute__((thiscall)) *)(void*, int, int, int*);
using Value = float(__attribute__((thiscall)) *)(void*, int, int, int*);
std::uintptr_t image;
native_input::Detour router;
Button originalPressed, originalTriggered;
Value originalValue;
bool installed;
void* kind(std::uint32_t entry) {
    return reinterpret_cast<void*>(image + entry);
}
bool __attribute__((fastcall)) pressed(void* manager, void*, int action, int controller,
                                       int* source) {
    return router(manager, nullptr, controller, kind(entry::inputPressed), &action, nullptr,
                  source);
}
bool __attribute__((fastcall)) triggered(void* manager, void*, int action, int controller,
                                         int* source) {
    return router(manager, nullptr, controller, kind(entry::inputTriggered), &action, nullptr,
                  source);
}
float __attribute__((fastcall)) value(void* manager, void*, int action, int controller,
                                      int* source) {
    float result = 0;
    router(manager, nullptr, controller, kind(entry::inputValue), &action, &result, source);
    return result;
}
bool __attribute__((thiscall)) physical(void* manager, int controller, void* callback,
                                        const int* action, void* result, int* source) {
    if (!installed || !action)
        return false;
    if (callback == kind(entry::inputPressed))
        return originalPressed(manager, *action, controller, source);
    if (callback == kind(entry::inputTriggered))
        return originalTriggered(manager, *action, controller, source);
    if (callback == kind(entry::inputValue)) {
        const auto value = originalValue(manager, *action, controller, source);
        if (result)
            *static_cast<float*>(result) = value;
        return value != 0;
    }
    // No arbitrary callback invocation, even for an unrecognized token.
    return false;
}
} // namespace
bool install(std::uintptr_t base, native_input::Detour detour, native_input::Query& original) {
    if (!base || !detour || installed)
        return false;
    image = base;
    router = detour;
    std::array<void*, 3> targets{};
    unsigned created = 0;
    auto hook = [&](std::uint32_t rva, auto replacement, auto& trampoline) {
        auto* target = reinterpret_cast<void*>(image + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(replacement),
                          reinterpret_cast<void**>(&trampoline)) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success = hook(entry::inputPressed, pressed, originalPressed) &&
                   hook(entry::inputTriggered, triggered, originalTriggered) &&
                   hook(entry::inputValue, value, originalValue);
    if (success) {
        // Supply the bypass before enabling a detour which may use it.
        original = physical;
        installed = true;
        for (auto* target : targets)
            if (MH_EnableHook(target) != MH_OK) {
                success = false;
                break;
            }
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        original = nullptr;
        installed = false;
        image = 0;
        router = nullptr;
        originalPressed = originalTriggered = nullptr;
        originalValue = nullptr;
    }
    return success;
}
} // namespace isaac::engine::j835::input_queries

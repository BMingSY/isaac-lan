#include "engine/versions/common/victory_prompt.h"
#include "engine/versions/common/victory_prompt_bindings.h"
#include "engine/input.h"
#include "core/input_actions.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <array>
#include <cstring>

namespace isaac::engine::native_victory_prompt {
namespace {
using Address = std::uintptr_t;
using Method = void(__attribute__((thiscall)) *)(void*);
Address image;
bool installed;
Method originalControls, originalRender;
constexpr int accept = 1, decline = 2;
template <class T> T& at(Address address, unsigned offset) {
    return *reinterpret_cast<T*>(address + offset);
}
Address prompt() {
    const auto game = image ? at<Address>(image, bindings.game) : 0;
    return game ? game + bindings.prompt : 0;
}
bool idle(Address address) {
    const auto animation = at<Address>(address, bindings.animation);
    constexpr unsigned idleLength = 4, inlineCapacity = 16;
    if (!animation || !at<bool>(address, bindings.playing) ||
        at<unsigned>(animation, bindings.stringSize) != idleLength)
        return false;
    const auto name = at<unsigned>(animation, bindings.stringCapacity) >= inlineCapacity
                          ? at<Address>(animation, 0)
                          : animation;
    return name && std::memcmp(reinterpret_cast<void*>(name), "Idle", idleLength) == 0;
}
bool partyPrompt(void* object) {
    const auto address = prompt();
    return address && runtime::localViewSlot() >= 0 && reinterpret_cast<Address>(object) == address;
}
void __attribute__((fastcall)) controls(void* object, void*) {
    if (!partyPrompt(object)) {
        originalControls(object);
        return;
    }
    const auto address = reinterpret_cast<Address>(object);
    if (runtime::challengeActive()) {
        if (idle(address)) {
            at<int>(address, bindings.result) = decline;
            reinterpret_cast<Method>(image + bindings.hide)(object);
        }
        return;
    }
    if (runtime::replica())
        return;
    // J460 has a Steam-vote field; the original game has no such field.
    if (bindings.nativeVote)
        at<bool>(address, *bindings.nativeVote) = false;
    // Native render edges do not last until every simulation step. Consume
    // the host's accepted, latched edges and leave animation updates native.
    const bool left = input::hostMenuTriggered(input::action::menuLeft) ||
                      input::hostMenuTriggered(input::action::menuRight);
    const bool confirm = input::hostMenuTriggered(input::action::menuConfirm);
    if (left) {
        auto& selection = at<int>(address, bindings.selection);
        selection = (static_cast<unsigned>(selection) - 1u) & 1u;
    }
    if (confirm && idle(address)) {
        at<int>(address, bindings.result) =
            at<int>(address, bindings.selection) == 0 ? decline : accept;
        reinterpret_cast<Method>(image + bindings.hide)(object);
    }
}
void __attribute__((fastcall)) render(void* object, void*) {
    if (!partyPrompt(object) || (!runtime::challengeActive() && runtime::localViewSlot() == 0))
        originalRender(object);
}
} // namespace
State read() {
    const auto address = prompt();
    if (!address)
        return {};
    return {at<Address>(address, bindings.animation) && at<bool>(address, bindings.playing),
            at<int>(address, bindings.selection), at<int>(address, bindings.result),
            bindings.nativeVote && at<bool>(address, *bindings.nativeVote), idle(address)};
}
bool install(Address base) {
    if (!base || installed)
        return false;
    image = base;
    std::array<void*, 2> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned rva, auto detour, Method& original) {
        auto* target = reinterpret_cast<void*>(base + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(detour),
                          reinterpret_cast<void**>(&original)) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success = hook(bindings.controls, controls, originalControls) &&
                   hook(bindings.render, render, originalRender);
    if (success) {
        for (unsigned i = 0; i < created; ++i)
            if (MH_QueueEnableHook(targets[i]) != MH_OK) {
                success = false;
                break;
            }
        if (success)
            success = MH_ApplyQueued() == MH_OK;
    }
    if (!success) {
        while (created)
            MH_RemoveHook(targets[--created]);
        image = 0;
        originalControls = originalRender = nullptr;
    }
    installed = success;
    return success;
}
} // namespace isaac::engine::native_victory_prompt

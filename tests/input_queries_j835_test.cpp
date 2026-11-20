#include "test_support.h"
#include "engine/versions/j835/input_queries.h"
#include "engine/versions/j835/input_actions.h"
#include "engine/versions/j835/entrypoints.h"
#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <MinHook.h>
#include <array>
#include <cstring>

namespace {
namespace backend = isaac::engine::j835;
namespace native = isaac::engine::native_input;
constexpr unsigned imageSize = 0x600000;
unsigned char* image;
std::array<unsigned char, 4> manager{};
native::Query physical;
bool passthrough = true;
unsigned nativeCalls, routed;
int expectedAction, expectedController;
using Button = bool(__attribute__((thiscall)) *)(void*, int, int, int*);
using Value = float(__attribute__((thiscall)) *)(void*, int, int, int*);
template <class Fn> Fn entry(unsigned rva) {
    return reinterpret_cast<Fn>(image + rva);
}
void* kind(unsigned rva) {
    return image + rva;
}
void patch(unsigned rva, auto fn) {
    image[rva] = 0xe9;
    const auto delta = static_cast<std::int32_t>(reinterpret_cast<std::uintptr_t>(fn) -
                                                 reinterpret_cast<std::uintptr_t>(image + rva + 5));
    std::memcpy(image + rva + 1, &delta, sizeof(delta));
    std::memset(image + rva + 5, 0x90, 11);
}
void check(void* receiver, int action, int controller, int* source) {
    require(receiver == manager.data() && action == expectedAction &&
                controller == expectedController,
            "Native thiscall receiver or argument order changed");
    if (source)
        *source = controller + 100;
    ++nativeCalls;
}
bool __attribute__((fastcall)) pressed(void* receiver, void*, int action, int controller,
                                       int* source) {
    check(receiver, action, controller, source);
    return action == 9;
}
bool __attribute__((fastcall)) triggered(void* receiver, void*, int action, int controller,
                                         int* source) {
    check(receiver, action, controller, source);
    return action == 10;
}
float __attribute__((fastcall)) value(void* receiver, void*, int action, int controller,
                                      int* source) {
    check(receiver, action, controller, source);
    return action == 0 ? 0.375f : 0;
}
bool __attribute__((fastcall)) route(void* receiver, void*, int controller, void* callback,
                                     const int* action, void* result, int* source) {
    require(receiver == manager.data() && action && *action == expectedAction &&
                controller == expectedController,
            "Unified query argument order changed");
    require(callback == kind(backend::entry::inputPressed) ||
                callback == kind(backend::entry::inputTriggered) ||
                callback == kind(backend::entry::inputValue),
            "Unexpected query kind token");
    ++routed;
    if (passthrough)
        return physical(receiver, controller, callback, action, result, source);
    if (source)
        *source = 42;
    if (callback == kind(backend::entry::inputValue)) {
        require(result, "Native float query needs an output buffer");
        *static_cast<float*>(result) = 0.625f;
        // The native float result is independent of the router's boolean return.
        return false;
    }
    require(!result, "Button query unexpectedly has a float buffer");
    return callback == kind(backend::entry::inputTriggered);
}
void setup() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Create standalone input fixture");
    patch(backend::entry::inputPressed, pressed);
    patch(backend::entry::inputTriggered, triggered);
    patch(backend::entry::inputValue, value);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    auto* conflict = kind(backend::entry::inputValue);
    require(MH_CreateHook(conflict, reinterpret_cast<void*>(value), nullptr) == MH_OK,
            "Prepare foreign hook conflict");
    require(!backend::input_queries::install(reinterpret_cast<std::uintptr_t>(image), route,
                                             physical) &&
                !physical,
            "Partially installed query adapters must fail and clear bypass");
    require(MH_RemoveHook(conflict) == MH_OK, "Rollback must preserve the foreign hook");
    require(
        backend::input_queries::install(reinterpret_cast<std::uintptr_t>(image), route, physical) &&
            physical,
        "Retry must succeed after complete rollback");
}
void nativePaths() {
    for (bool pass : {true, false}) {
        passthrough = pass;
        for (int controller : {-1, 0, 1, 4, 8}) {
            expectedController = controller;
            for (int action : {-5, 0, 9, 10, 16, 20, 99}) {
                expectedAction = action;
                int source = -777;
                nativeCalls = routed = 0;
                const auto held = entry<Button>(backend::entry::inputPressed)(
                    manager.data(), action, controller, &source);
                require(held == (pass && action == 9), "Pressed return ABI");
                const auto edge = entry<Button>(backend::entry::inputTriggered)(
                    manager.data(), action, controller, &source);
                require(edge == (!pass || action == 10), "Triggered return ABI");
                const auto analog = entry<Value>(backend::entry::inputValue)(manager.data(), action,
                                                                             controller, &source);
                require(analog == (pass ? (action == 0 ? 0.375f : 0) : 0.625f),
                        "Float x87 return ABI");
                require(routed == 3 && nativeCalls == (pass ? 3u : 0u) &&
                            source == (pass ? controller + 100 : 42),
                        "Query routing, suppression or source output");
            }
        }
    }
}
void bypass() {
    passthrough = false;
    expectedController = 3;
    expectedAction = 0;
    nativeCalls = routed = 0;
    int source = -1;
    float output = -1;
    require(physical(manager.data(), 3, kind(backend::entry::inputValue), &expectedAction, &output,
                     &source) &&
                output == 0.375f && source == 103 && nativeCalls == 1 && routed == 0,
            "Physical bypass must not reenter a gameplay hook");
    require(physical(manager.data(), 3, kind(backend::entry::inputValue), &expectedAction, nullptr,
                     nullptr),
            "Optional float and source outputs");
    expectedAction = 9;
    require(physical(manager.data(), 3, kind(backend::entry::inputPressed), &expectedAction,
                     nullptr, nullptr),
            "Physical pressed bypass");
    expectedAction = 10;
    require(physical(manager.data(), 3, kind(backend::entry::inputTriggered), &expectedAction,
                     nullptr, nullptr),
            "Physical edge bypass");
    const auto count = nativeCalls;
    require(!physical(manager.data(), 3, nullptr, &expectedAction, &output, &source) &&
                !physical(manager.data(), 3, kind(backend::entry::inputValue), nullptr, &output,
                          &source) &&
                count == nativeCalls,
            "Invalid query tokens must not invoke arbitrary callbacks or native methods");
    const auto previous = physical;
    require(!backend::input_queries::install(reinterpret_cast<std::uintptr_t>(image), route,
                                             physical) &&
                physical == previous,
            "Duplicate installation must preserve the installed bypass");
}
} // namespace
int main() {
    static_assert(backend::input_actions::restart == 16);
    static_assert(backend::input_actions::menuLeft == 20 && backend::input_actions::menuDown == 23);
    setup();
    nativePaths();
    bypass();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release input fixture");
}

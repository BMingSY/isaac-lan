// Exercise the x86 calling boundary in private memory; no game is started.
#include "test_support.h"
#include "engine/versions/j460/stage_transition_binding.h"
#include <array>
#include <cstring>

namespace {
using Address = std::uintptr_t;
using Method = void(__attribute__((thiscall)) *)(void*, bool, int, void*);
struct Arguments {
    Method method;
    void* game;
    unsigned same;
    int animation;
    void* player;
    int argumentCount = 4;
};
struct Observation {
    Address before, after, esi, edi;
};
Arguments observed{};
void __attribute__((thiscall)) stage(void* game, bool same, int animation, void* player) {
    observed = {stage, game, same, animation, player};
}
void __attribute__((thiscall)) nextStage(void* game, bool same, int animation, void* player) {
    observed = {nextStage, game, same, animation, player};
}
using Binding = int(__cdecl*)(Arguments*);
// Model the stock Lua thunk: two pushed arguments, followed by saved EDI/ESI.
// The method's ret 12 consumes saved EDI, so the thunk restores the wrong ESI.
int __attribute__((naked, cdecl)) twoArguments(Arguments*) {
    asm volatile("push %ebp; mov %esp,%ebp; sub $16,%esp; push %esi; push %edi;"
                 "mov 8(%ebp),%edi; movl $0x80008401,-16(%ebp);"
                 "push 12(%edi); push 8(%edi); mov 4(%edi),%ecx; call *(%edi);"
                 "pop %edi; pop %esi; xor %eax,%eax; mov %ebp,%esp; pop %ebp; ret");
}
int __cdecl threeArguments(Arguments* args) {
    require(args->argumentCount >= 4, "Native adapter received an absent player argument");
    args->method(args->game, args->same != 0, args->animation, args->player);
    return 0;
}
int __cdecl argumentCount(lua_State* state) {
    return reinterpret_cast<Arguments*>(state)->argumentCount;
}
void __cdecl setArgumentCount(lua_State* state, int count) {
    auto& args = *reinterpret_cast<Arguments*>(state);
    require(args.argumentCount == 3 && count == 4, "Unexpected Lua argument change");
    args.argumentCount = count;
    args.player = nullptr;
}
void __attribute__((naked, cdecl)) inspect(Binding, Arguments*, Observation*) {
    asm volatile("push %ebp; mov %esp,%ebp; push %ebx; push %esi; push %edi;"
                 "mov 16(%ebp),%ebx; mov %esp,(%ebx);"
                 "mov $0x80008404,%esi; mov $0x12345678,%edi;"
                 "push 12(%ebp); call *8(%ebp); add $4,%esp;"
                 "mov %esp,4(%ebx); mov %esi,8(%ebx); mov %edi,12(%ebx);"
                 "pop %edi; pop %esi; pop %ebx; pop %ebp; ret");
}
void entry(unsigned char* target, Binding function) {
    // A relocatable prologue lets MinHook install the same redirect as in-game.
    std::array<unsigned char, 11> bytes{0x55, 0x8b, 0xec, 0x5d, 0xb8, 0, 0, 0, 0, 0xff, 0xe0};
    const auto address = reinterpret_cast<Address>(function);
    std::memcpy(bytes.data() + 5, &address, sizeof(address));
    std::memcpy(target, bytes.data(), bytes.size());
}
} // namespace

int main() {
    namespace native = isaac::engine::j460;
    auto* image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, native::entry::luaPlayerTransitionBinding + 64,
                     MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    try {
        require(image != nullptr && MH_Initialize() == MH_OK, "Cannot prepare private ABI image");
        const auto base = reinterpret_cast<Address>(image);
        entry(image + native::entry::luaStageTransitionBinding, twoArguments);
        entry(image + native::entry::luaPlayerTransitionBinding, threeArguments);
        const auto binding =
            reinterpret_cast<Binding>(image + native::entry::luaStageTransitionBinding);
        require(!native::installStageTransitionBinding(base, {}), "Missing Lua API accepted");
        std::array<int, 3> games{}, players{};
        Arguments args{stage, &games[0], true, 6, &players[0]};
        Observation call{};
        inspect(binding, &args, &call);
        require(call.esi != 0x80008404 && observed.player != args.player,
                "Old two-argument boundary did not reproduce register/actor corruption");
        isaac::lua::API api;
        api.getTop = argumentCount;
        api.setTop = setArgumentCount;
        require(native::installStageTransitionBinding(base, api), "Cannot install stage binding");
        for (unsigned generation = 0; generation < 3; ++generation) {
            // New Lua closures keep their own method/arguments; the redirect owns no state.
            Arguments next{generation == 1 ? nextStage : stage, &games[generation], generation != 0,
                           static_cast<int>(generation),
                           generation == 1 ? nullptr : &players[generation]};
            for (unsigned repeat = 0; repeat < 20; ++repeat) {
                inspect(binding, &next, &call);
                require(call.before == call.after && call.esi == 0x80008404 &&
                            call.edi == 0x12345678,
                        "Stage binding changed the caller's stack or saved Lua registers");
                require(observed.method == next.method && observed.game == next.game &&
                            observed.same == next.same && observed.animation == next.animation &&
                            observed.player == next.player,
                        "Stage binding lost a native argument or retained an old closure");
            }
        }
        Arguments omitted{stage, &games[0], false, 0, &players[0], 3};
        inspect(binding, &omitted, &call);
        require(omitted.argumentCount == 4 && observed.player == nullptr &&
                    call.before == call.after && call.esi == 0x80008404 && call.edi == 0x12345678,
                "Omitted player was not safely padded with nil");
        Arguments extra{stage, &games[0], false, 0, &players[0], 5};
        inspect(binding, &extra, &call);
        require(extra.argumentCount == 5 && observed.player == extra.player,
                "Explicit player or extra Lua arguments were changed");
        require(MH_RemoveHook(image + native::entry::luaStageTransitionBinding) == MH_OK,
                "Cannot remove private hook");
        inspect(binding, &args, &call);
        require(call.esi != 0x80008404, "Uninstall did not restore the original boundary");
        MH_Uninitialize();
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS stage binding, saved registers, stack, optional actor and fresh closures");
        return 0;
    } catch (const std::exception& error) {
        MH_Uninitialize();
        if (image)
            VirtualFree(image, 0, MEM_RELEASE);
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

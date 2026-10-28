#include "engine/versions/common/room_routing.h"
#include "engine/versions/common/room_routing_bindings.h"
#include "compat/routes/curses.h"
#include <MinHook.h>
#include <array>
#include <exception>
#include <stdexcept>

namespace isaac::engine::native_room_routing {
namespace {
std::uintptr_t image;
bool installed;
struct Resolution {
    const std::function<bool(RoomArrival)>& prepare;
    bool reached = false;
    std::exception_ptr error{};
};
Resolution* pending = nullptr;
template <class T> T read(std::uintptr_t base, std::ptrdiff_t offset) {
    return *reinterpret_cast<const T*>(base + offset);
}
} // namespace
void withResolvedRoomEntry(const std::function<bool(RoomArrival)>& prepare,
                           const std::function<void()>& change) {
    if (pending)
        throw std::runtime_error("Nested native room resolution");
    Resolution resolution{prepare};
    struct Reset {
        ~Reset() {
            pending = nullptr;
        }
    } reset;
    pending = &resolution;
    change();
    if (resolution.error)
        std::rethrow_exception(resolution.error);
    if (!resolution.reached)
        throw std::runtime_error("Native room resolution did not reach its entry boundary");
}
std::uint32_t currentCurses() {
    const auto game = image ? read<std::uintptr_t>(image, bindings.game) : 0;
    if (!game)
        return 0;
    using Mask = std::uint32_t(__cdecl*)();
    return (read<std::uint32_t>(game, bindings.layout.curses) |
            read<std::uint32_t>(game, bindings.layout.seedCurses) |
            reinterpret_cast<Mask>(image + bindings.entry.addedCurses)()) &
           ~reinterpret_cast<Mask>(image + bindings.entry.removedCurses)();
}
extern "C" {
void* isaac_lan_room_resolved_original = nullptr;
void* isaac_lan_room_resolved_return = nullptr;
bool isaac_lan_room_suppress_maze = false;
void* isaac_lan_room_maze_original = nullptr;
void* isaac_lan_room_maze_end = nullptr;
__attribute__((naked)) void isaac_lan_room_maze_thunk() {
    __asm__ __volatile__("pushfl\n\tcmpb $0, _isaac_lan_room_suppress_maze\n\tjne 1f\n\t"
                         "popfl\n\tjmp *_isaac_lan_room_maze_original\n\t1:\n\t"
                         "popfl\n\tjmp *_isaac_lan_room_maze_end");
}
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_room_resolved_prepare(
    std::uintptr_t* registers) {
    enum Register : unsigned { frame = 2, continuation = 9 };
    registers[continuation] = reinterpret_cast<std::uintptr_t>(isaac_lan_room_resolved_original);
    if (!pending || pending->reached)
        return;
    pending->reached = true;
    bool initialize = false;
    try {
        const auto game = image ? read<std::uintptr_t>(image, bindings.game) : 0;
        if (!game)
            throw std::runtime_error("Native room resolution lost its Game");
        initialize = pending->prepare(
            {read<int>(game, bindings.layout.roomIndex), read<int>(game, bindings.layout.dimension),
             read<int>(game, bindings.layout.enterDoor),
             read<unsigned char>(registers[frame], bindings.layout.redirected) != 0});
    } catch (...) {
        pending->error = std::current_exception();
    }
    if (!initialize)
        registers[continuation] = reinterpret_cast<std::uintptr_t>(isaac_lan_room_resolved_return);
}
// Save all live integer, flag, SSE and x87 state, including control words.
// The extra return slot selects the trampoline or the native common epilogue.
__attribute__((naked)) void isaac_lan_room_resolved_thunk() {
    __asm__ __volatile__("pushl $0\n\tpushfl\n\tpushal\n\tmovl %esp, %eax\n\t"
                         "subl $528, %esp\n\tandl $-16, %esp\n\tfxsave (%esp)\n\t"
                         "movl %eax, 512(%esp)\n\tpushl %eax\n\t"
                         "call _isaac_lan_room_resolved_prepare\n\taddl $4, %esp\n\t"
                         "fxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\tret");
}
} // extern "C"
void withoutRoomCurseRouting(const std::function<void()>& change) {
    compat::routes::ResolvedRoomCurses scope(isaac_lan_room_suppress_maze);
    change();
}
bool installRoomRouting(std::uintptr_t base) {
    if (!base || installed)
        return false;
    image = base;
    isaac_lan_room_resolved_return = reinterpret_cast<void*>(base + bindings.entry.roomReturn);
    isaac_lan_room_maze_end = reinterpret_cast<void*>(base + bindings.entry.mazeEnd);
    std::array<void*, 2> targets{};
    unsigned created = 0;
    auto hook = [&](unsigned rva, auto detour, void*& original) {
        auto* target = reinterpret_cast<void*>(base + rva);
        if (MH_CreateHook(target, reinterpret_cast<void*>(detour), &original) != MH_OK)
            return false;
        targets[created++] = target;
        return true;
    };
    bool success =
        hook(bindings.entry.resolved, isaac_lan_room_resolved_thunk,
             isaac_lan_room_resolved_original) &&
        hook(bindings.entry.maze, isaac_lan_room_maze_thunk, isaac_lan_room_maze_original);
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
        isaac_lan_room_resolved_original = isaac_lan_room_resolved_return = nullptr;
        isaac_lan_room_maze_original = isaac_lan_room_maze_end = nullptr;
    }
    installed = success;
    return success;
}
} // namespace isaac::engine::native_room_routing

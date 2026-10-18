#include "engine/versions/j460/room_routing.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "compat/routes/curses.h"
#include <MinHook.h>
#include <exception>
#include <stdexcept>

namespace isaac::engine::j460 {
namespace {
std::uintptr_t image;
struct Resolution {
    const std::function<bool(RoomArrival)>& prepare;
    bool reached = false;
    std::exception_ptr error{};
};
Resolution* pending = nullptr;
template <class T> T read(std::uintptr_t base, unsigned offset) {
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
    const auto game = read<std::uintptr_t>(image, globals::game);
    using Mask = std::uint32_t(__cdecl*)();
    return (read<std::uint32_t>(game, layout::game::curses) |
            read<std::uint32_t>(game, layout::game::seedCurses) |
            reinterpret_cast<Mask>(image + entry::gameAddedSeedCurses)()) &
           ~reinterpret_cast<Mask>(image + entry::gameRemovedSeedCurses)();
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
__attribute__((used, force_align_arg_pointer)) bool __cdecl isaac_lan_room_resolved_prepare(
    std::uintptr_t nativeFrame) {
    if (!pending || pending->reached)
        return true;
    pending->reached = true;
    try {
        const auto game = read<std::uintptr_t>(image, globals::game);
        return pending->prepare(
            {read<int>(game, layout::game::roomIndex), read<int>(game, layout::game::dimension),
             read<int>(game, layout::game::enterDoor),
             read<unsigned char>(nativeFrame, layout::roomChangeFrame::mazeRedirected) != 0});
    } catch (...) {
        pending->error = std::current_exception();
        return false;
    }
}
#define SAVE_ROOM_REGISTERS                                                                        \
    "pushfl\n\tpushal\n\tsubl $128, %esp\n\t"                                                      \
    "movups %xmm0, 0(%esp)\n\tmovups %xmm1, 16(%esp)\n\t"                                          \
    "movups %xmm2, 32(%esp)\n\tmovups %xmm3, 48(%esp)\n\t"                                         \
    "movups %xmm4, 64(%esp)\n\tmovups %xmm5, 80(%esp)\n\t"                                         \
    "movups %xmm6, 96(%esp)\n\tmovups %xmm7, 112(%esp)\n\t"
#define RESTORE_ROOM_REGISTERS                                                                     \
    "movups 0(%esp), %xmm0\n\tmovups 16(%esp), %xmm1\n\t"                                          \
    "movups 32(%esp), %xmm2\n\tmovups 48(%esp), %xmm3\n\t"                                         \
    "movups 64(%esp), %xmm4\n\tmovups 80(%esp), %xmm5\n\t"                                         \
    "movups 96(%esp), %xmm6\n\tmovups 112(%esp), %xmm7\n\t"                                        \
    "addl $128, %esp\n\tpopal\n\tpopfl\n\t"
// At 0x3404ec all native Maze containers have been destroyed, the final room
// and EnterDoor are set, and no destination objects have been initialized.
// The common epilogue restores the native SEH frame and pops both arguments.
__attribute__((naked)) void isaac_lan_room_resolved_thunk() {
    __asm__ __volatile__(SAVE_ROOM_REGISTERS
                         "pushl %ebp\n\tcall _isaac_lan_room_resolved_prepare\n\t"
                         "addl $4, %esp\n\ttestb %al, %al\n\tjz "
                         "1f\n\t" RESTORE_ROOM_REGISTERS
                         "jmp *_isaac_lan_room_resolved_original\n\t1:\n\t" RESTORE_ROOM_REGISTERS
                         "jmp *_isaac_lan_room_resolved_return");
}
#undef SAVE_ROOM_REGISTERS
#undef RESTORE_ROOM_REGISTERS
}
void withoutRoomCurseRouting(const std::function<void()>& change) {
    compat::routes::ResolvedRoomCurses scope(isaac_lan_room_suppress_maze);
    change();
}
bool installRoomRouting(std::uintptr_t base) {
    image = base;
    isaac_lan_room_resolved_return = reinterpret_cast<void*>(image + entry::levelRoomChangeReturn);
    isaac_lan_room_maze_end = reinterpret_cast<void*>(image + entry::levelMazeBranchEnd);
    const auto site = reinterpret_cast<void*>(image + entry::levelRoomEntryResolved);
    const auto maze = reinterpret_cast<void*>(image + entry::levelMazeBranch);
    return MH_CreateHook(site, reinterpret_cast<void*>(isaac_lan_room_resolved_thunk),
                         &isaac_lan_room_resolved_original) == MH_OK &&
           MH_CreateHook(maze, reinterpret_cast<void*>(isaac_lan_room_maze_thunk),
                         &isaac_lan_room_maze_original) == MH_OK &&
           MH_EnableHook(site) == MH_OK && MH_EnableHook(maze) == MH_OK;
}
} // namespace isaac::engine::j460

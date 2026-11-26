#include "engine/versions/common/player_seats.h"
#include "engine/player_outlines.h"
#include "engine/versions/common/player_outlines.h"
#include "engine/versions/repentance/entrypoints.h"
#include "engine/versions/repentance/layout.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <cstring>

namespace isaac::presentation::outlines {
namespace {
namespace backend = engine::repentance;
namespace layout = backend::layout;
using Address = std::uintptr_t;
using Vector = std::array<float, 2>;
static_assert(sizeof(Color) == layout::color::size);
Address image = 0;
bool installed = false;
struct Boundary {
    unsigned gate, color;
    void* original = nullptr;
};
std::array<Boundary, 3> boundaries{{
    {backend::entry::playerOutlineBodyGate, backend::entry::playerOutlineBodyColor},
    {backend::entry::playerOutlineSpecialGate, backend::entry::playerOutlineSpecialColor},
    {backend::entry::playerOutlineGhostGate, 0},
}};
template <class T> T& at(Address object, std::ptrdiff_t offset) {
    return *reinterpret_cast<T*>(object + offset);
}
std::optional<unsigned> slot(Address player) {
    return player ? controllerSlot(isaac::engine::player_seats::owner(
                        player, at<int>(player, layout::player::controller)))
                  : std::nullopt;
}
void drawGhost(Address player, Address offset, const Color& color) {
    if (!offset)
        return;
    const auto stack = image + backend::globals::colorStack;
    struct Restore {
        Address stack, player;
        unsigned count;
        Vector position;
        ~Restore() {
            // Push may grow the native deque. Retain its allocation and normalized
            // first index; only remove colors introduced by this draw scope.
            at<unsigned>(stack, layout::colorStack::count) = count;
            if (!count)
                at<unsigned>(stack, layout::colorStack::first) = 0;
            at<Vector>(player, layout::entity::renderPosition) = position;
        }
    } restore{stack, player, at<unsigned>(stack, layout::colorStack::count),
              at<Vector>(player, layout::entity::renderPosition)};
    using Push = void(__attribute__((thiscall))*)(const Color*);
    using Render = void(__attribute__((thiscall))*)(void*, const Vector*);
    reinterpret_cast<Push>(image + backend::entry::colorStackPush)(&color);
    const auto origin = at<Vector>(offset, 0);
    constexpr std::array<Vector, 4> directions{{{-1, 0}, {0, -1}, {1, 0}, {0, 1}}};
    for (const auto& direction : directions) {
        const Vector point{origin[0] + direction[0], origin[1] + direction[1]};
        reinterpret_cast<Render>(image + backend::entry::entityRender)(
            reinterpret_cast<void*>(player), &point);
    }
}
} // namespace
extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_repentance_outline_prepare(
    Address* registers, unsigned index) {
    // pushad saves EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX, flags, continuation.
    // Repentance owns EDI=player and ESI=render offset, unlike Repentance+'s EBX player.
    enum Register : unsigned { player = 0, offset = 1, frame = 2, receiver = 6, continuation = 9 };
    const auto& boundary = boundaries[index];
    registers[continuation] = reinterpret_cast<Address>(boundary.original);
    const auto owner = slot(registers[player]);
    if (!owner || !at<bool>(registers[frame], layout::playerRenderFrame::mainPass))
        return;
    const auto color = nativeColor(*owner);
    if (boundary.color) {
        if (at<bool>(registers[frame], layout::playerRenderFrame::hologram))
            return;
        // Enter at the native color-stack call after supplying its complete
        // temporary ColorMod. Native body/head/costume draw and pop stay intact.
        const auto destination = registers[frame] + layout::playerRenderFrame::color;
        std::memcpy(reinterpret_cast<void*>(destination), color.data(), sizeof(color));
        registers[receiver] = destination;
        registers[continuation] = image + boundary.color;
    } else {
        try {
            // The original ghost branch draws its normal Sprite after this scope.
            drawGhost(registers[player], registers[offset], color);
        } catch (const std::exception& error) {
            runtime::abort(error.what());
        }
    }
}
#define OUTLINE_BOUNDARY(NAME, INDEX)                                                              \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__("pushl $0\n\tpushfl\n\tpushal\n\tmovl %esp, %eax\n\t"                 \
                             "andl $-16, %esp\n\tsubl $528, %esp\n\tmovl %eax, 512(%esp)\n\t"      \
                             "fxsave (%esp)\n\tpushl $" #INDEX "\n\tpushl %eax\n\t"                \
                             "call _isaac_lan_repentance_outline_prepare\n\taddl $8, %esp\n\t"     \
                             "fxrstor (%esp)\n\tmovl 512(%esp), %esp\n\tpopal\n\tpopfl\n\tret");   \
    }
OUTLINE_BOUNDARY(isaac_lan_repentance_outline_body, 0)
OUTLINE_BOUNDARY(isaac_lan_repentance_outline_special, 1)
OUTLINE_BOUNDARY(isaac_lan_repentance_outline_ghost, 2)
#undef OUTLINE_BOUNDARY
}
bool install(Address base) {
    if (!base || installed)
        return false;
    image = base;
    const std::array<void (*)(), 3> detours{isaac_lan_repentance_outline_body,
                                            isaac_lan_repentance_outline_special,
                                            isaac_lan_repentance_outline_ghost};
    unsigned created = 0;
    const auto rollback = [&] {
        for (unsigned i = 0; i < created; ++i) {
            MH_RemoveHook(reinterpret_cast<void*>(image + boundaries[i].gate));
            boundaries[i].original = nullptr;
        }
        image = 0;
    };
    for (unsigned i = 0; i < boundaries.size(); ++i) {
        if (MH_CreateHook(reinterpret_cast<void*>(image + boundaries[i].gate),
                          reinterpret_cast<void*>(detours[i]), &boundaries[i].original) != MH_OK) {
            rollback();
            return false;
        }
        ++created;
    }
    for (const auto& boundary : boundaries)
        if (MH_EnableHook(reinterpret_cast<void*>(image + boundary.gate)) != MH_OK) {
            rollback();
            return false;
        }
    installed = true;
    return true;
}
} // namespace isaac::presentation::outlines

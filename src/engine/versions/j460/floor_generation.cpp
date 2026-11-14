#include "engine/floor_generation.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include <MinHook.h>

namespace isaac::engine {
namespace {
bool (*useLargeFloor)() = nullptr;
constexpr unsigned nativeLargeFloorChallenge = 21;
constexpr unsigned compareBytes = 7;
constexpr std::uint32_t arithmeticFlags = 0x8d5, equalFlags = 0x44;
void* originals[2]{};
} // namespace
extern "C" {
void* isaac_lan_floor_count_return = nullptr;
void* isaac_lan_floor_shape_return = nullptr;
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_floor_prepare(
    std::uint32_t* registers) {
    // pushad follows pushfd: EDI, ESI, EBP, ESP, EBX, EDX, ECX, EAX, EFLAGS.
    // Preserve the native comparison unless the caller requests its equal branch.
    if (useLargeFloor && useLargeFloor())
        registers[8] = (registers[8] & ~arithmeticFlags) | equalFlags;
}

#define ISAAC_LAN_FLOOR_THUNK(destination)                                                         \
    __asm__ __volatile__(                                                                          \
        "cmpl $%c[challenge], %c[offset](%%eax)\n\t"                                               \
        "pushfl\n\tpushal\n\tsubl $128, %%esp\n\t"                                                 \
        "movups %%xmm0, (%%esp)\n\tmovups %%xmm1, 16(%%esp)\n\t"                                   \
        "movups %%xmm2, 32(%%esp)\n\tmovups %%xmm3, 48(%%esp)\n\t"                                 \
        "movups %%xmm4, 64(%%esp)\n\tmovups %%xmm5, 80(%%esp)\n\t"                                 \
        "movups %%xmm6, 96(%%esp)\n\tmovups %%xmm7, 112(%%esp)\n\t"                                \
        "leal 128(%%esp), %%eax\n\tpushl %%eax\n\tcall _isaac_lan_floor_prepare\n\t"               \
        "addl $4, %%esp\n\tmovups (%%esp), %%xmm0\n\tmovups 16(%%esp), %%xmm1\n\t"                 \
        "movups 32(%%esp), %%xmm2\n\tmovups 48(%%esp), %%xmm3\n\t"                                 \
        "movups 64(%%esp), %%xmm4\n\tmovups 80(%%esp), %%xmm5\n\t"                                 \
        "movups 96(%%esp), %%xmm6\n\tmovups 112(%%esp), %%xmm7\n\t"                                \
        "addl $128, %%esp\n\tpopal\n\tpopfl\n\tjmp *_" #destination                                \
        :                                                                                          \
        : [challenge] "i"(nativeLargeFloorChallenge), [offset] "i"(j460::layout::game::challenge))

__attribute__((naked)) void isaac_lan_floor_count() {
    ISAAC_LAN_FLOOR_THUNK(isaac_lan_floor_count_return);
}
__attribute__((naked)) void isaac_lan_floor_shape() {
    ISAAC_LAN_FLOOR_THUNK(isaac_lan_floor_shape_return);
}
#undef ISAAC_LAN_FLOOR_THUNK
}

bool installFloorGeneration(std::uintptr_t image, bool (*largeFloor)()) {
    useLargeFloor = largeFloor;
    isaac_lan_floor_count_return =
        reinterpret_cast<void*>(image + j460::entry::levelLargeFloorCount + compareBytes);
    isaac_lan_floor_shape_return =
        reinterpret_cast<void*>(image + j460::entry::levelLargeFloorShape + compareBytes);
    auto hook = [image](unsigned entry, void* detour, void** original) {
        auto target = reinterpret_cast<void*>(image + entry);
        return MH_CreateHook(target, detour, original) == MH_OK && MH_EnableHook(target) == MH_OK;
    };
    return hook(j460::entry::levelLargeFloorCount, reinterpret_cast<void*>(isaac_lan_floor_count),
                &originals[0]) &&
           hook(j460::entry::levelLargeFloorShape, reinterpret_cast<void*>(isaac_lan_floor_shape),
                &originals[1]);
}
} // namespace isaac::engine

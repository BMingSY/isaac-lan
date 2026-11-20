#include "engine/floor_generation.h"
#include "engine/versions/common/floor_generation_bindings.h"
#include "engine/versions/common/branch_frame.h"
#include "engine/versions/common/hooks.h"
#include "runtime/session.h"

namespace isaac::engine {
namespace {
bool (*useLargeFloor)() = nullptr;
constexpr std::uint32_t arithmeticFlags = 0x8d5, equalFlags = 0x44;
std::array<void*, 2> floorOriginals{};
std::uintptr_t floorImage = 0;
bool floorInstalled = false;
} // namespace
extern "C" {
__attribute__((used, force_align_arg_pointer)) void __cdecl isaac_lan_floor_prepare(
    native_branch::Frame* frame, unsigned index) noexcept {
    (*frame)[native_branch::continuation] = reinterpret_cast<std::uintptr_t>(floorOriginals[index]);
    try {
        if (useLargeFloor && useLargeFloor())
            (*frame)[native_branch::flags] =
                ((*frame)[native_branch::flags] & ~arithmeticFlags) | equalFlags;
    } catch (const std::exception& error) {
        runtime::abort(error.what());
    } catch (...) {
        runtime::abort("Native floor generation callback failed");
    }
}
#define FLOOR_BOUNDARY(NAME, INDEX)                                                                \
    __attribute__((naked)) void NAME() {                                                           \
        __asm__ __volatile__(                                                                      \
            ISAAC_LAN_NATIVE_BRANCH_SAVE                                                           \
            "pushl $" #INDEX "\n\tpushl %eax\n\t"                                                  \
            "call _isaac_lan_floor_prepare\n\taddl $8, %esp\n\t" ISAAC_LAN_NATIVE_BRANCH_RESTORE); \
    }
FLOOR_BOUNDARY(isaac_lan_floor_count, 0)
FLOOR_BOUNDARY(isaac_lan_floor_shape, 1)
#undef FLOOR_BOUNDARY
}
bool installFloorGeneration(std::uintptr_t image, bool (*largeFloor)()) {
    if (floorInstalled)
        return image == floorImage && largeFloor == useLargeFloor;
    if (!image)
        return false;
    const auto& binding = native_floor_generation::bindings;
    native_hooks::Group<2> hooks;
    useLargeFloor = largeFloor;
    floorImage = image;
    if (!hooks.add(image + binding.count + native_floor_generation::comparisonBytes,
                   isaac_lan_floor_count, floorOriginals[0]) ||
        !hooks.add(image + binding.shape + native_floor_generation::comparisonBytes,
                   isaac_lan_floor_shape, floorOriginals[1]) ||
        !hooks.enable()) {
        floorImage = 0;
        useLargeFloor = nullptr;
        return false;
    }
    floorInstalled = true;
    return true;
}
} // namespace isaac::engine

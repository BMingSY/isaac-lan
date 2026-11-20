#include "test_support.h"
#include "native_branch.h"
#include "engine/moving_box.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned seedOffset = 0x344, beginOffset = 0x1c9c, endOffset = 0x1ca0, playerRegister = 0;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
constexpr unsigned seedOffset = 0x3ec, beginOffset = 0x1d7c, endOffset = 0x1d80, playerRegister = 6;
#endif
#include <windows.h>
#include <MinHook.h>
#include <cstring>

extern "C" {
unsigned boxChoice = 0;
__attribute__((naked)) void boxFull() {
    __asm__ __volatile__("movl $1, _boxChoice\n\tret");
}
__attribute__((naked)) void boxEmpty() {
    __asm__ __volatile__("movl $0, _boxChoice\n\tret");
}
}
namespace {
namespace box = isaac::presentation::moving_box;
using Address = std::uintptr_t;
bool guest = false, disturb = false;
std::array<unsigned char, 0x2000> player{};
unsigned char* image = nullptr;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void patch(unsigned rva, void* target) {
    image[rva] = 0xe9;
    field<std::int32_t>(image, rva + 1) =
        reinterpret_cast<Address>(target) - reinterpret_cast<Address>(image + rva + 5);
    std::memset(image + rva + 5, 0x90, 11);
}
void install() {
    constexpr unsigned imageSize = 0x600000;
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize box fixture");
    patch(backend::entry::movingBoxHudFull, reinterpret_cast<void*>(boxFull));
    patch(backend::entry::movingBoxHudEmpty, reinterpret_cast<void*>(boxEmpty));
    auto* branch = image + backend::entry::movingBoxHudBranch;
    branch[0] = 0x0f;
    branch[1] = 0x84; // Original empty-vector JE, with its six-byte instruction.
    field<int>(branch, 2) =
        backend::entry::movingBoxHudEmpty - backend::entry::movingBoxHudBranch - 6;
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    const auto base = reinterpret_cast<Address>(image);
    require(!box::install(0), "Missing box image accepted");
    require(MH_CreateHook(branch, reinterpret_cast<void*>(boxEmpty), nullptr) == MH_OK,
            "Prepare foreign HUD hook");
    require(!box::install(base), "Conflicting HUD hook accepted");
    require(MH_CreateHook(branch, reinterpret_cast<void*>(boxEmpty), nullptr) ==
                MH_ERROR_ALREADY_CREATED,
            "Failed box install removed foreign hook");
    require(MH_RemoveHook(branch) == MH_OK && box::install(base) && !box::install(base),
            "HUD install did not recover or allowed duplicate hooks");
}
void expect(bool full) {
    const auto before = player;
    native_fixture::Registers registers{0x11112222, 0x22223333, 0x33334444, 0,
                                        0x44445555, 0x55556666, 0x66667777, 0x77778888};
    registers[playerRegister] = reinterpret_cast<Address>(player.data());
    disturb = true;
    const auto result =
        native_fixture::branch(image + backend::entry::movingBoxHudBranch, registers);
    disturb = false;
    require(boxChoice == full && result.balanced && result.floatingPreserved &&
                (result.flags & 0x41) == 0x41 && player == before,
            "HUD choice changed contents, stack, flags or floating state");
    for (unsigned i = 0; i < registers.size(); ++i)
        if (i != 3)
            require(result.registers[i] == registers[i], "HUD branch changed a general register");
}
void behavior() {
    const auto address = reinterpret_cast<Address>(player.data());
    field<unsigned>(player.data(), seedOffset) = 37;
    expect(false);
    field<Address>(player.data(), beginOffset) = 0x1000;
    field<Address>(player.data(), endOffset) = 0x1010;
    expect(true);
    guest = true;
    for (bool full : {false, true, true, false}) {
        box::apply(address, full);
        expect(full);
        require(box::capture(address) == full, "Captured replica view differs from its HUD");
    }
    ++field<unsigned>(player.data(), seedOffset);
    expect(true); // Same allocation, new native entity identity.
    box::apply(address, false);
    box::reset();
    expect(true);
    box::apply(address, false);
    guest = false;
    expect(true); // Authoritative captures always follow native contents.
    box::reset();
}
} // namespace
namespace isaac::runtime {
bool replica() {
    if (disturb) {
        unsigned control;
        __asm__ __volatile__("stmxcsr %0" : "=m"(control));
        control ^= 0x6000;
        __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0"
                             :
                             : "m"(control)
                             : "xmm7");
    }
    return guest;
}
} // namespace isaac::runtime
int main() {
    install();
    behavior();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release box fixture");
}

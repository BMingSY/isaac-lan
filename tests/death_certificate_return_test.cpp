#include "test_support.h"
#include "native_branch.h"
#include "engine/rooms.h"
#include "engine/versions/common/death_certificate_return.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#include "engine/versions/j835/layout.h"
namespace backend = isaac::engine::j835;
#else
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
namespace backend = isaac::engine::j460;
#endif
#include <windows.h>
#include <MinHook.h>
#include <cstring>
#include <vector>

extern "C" {
unsigned certificatePath = 0;
__attribute__((naked)) void certificateNative() {
    __asm__ __volatile__("movl $1, _certificatePath\n\tret");
}
__attribute__((naked)) void certificateDone() {
    __asm__ __volatile__("movl $2, _certificatePath\n\tret");
}
}
namespace {
using Address = std::uintptr_t;
constexpr unsigned imageSize = 0xa00000;
unsigned char* image = nullptr;
std::vector<unsigned char> game(backend::layout::game::deathCertificateReturnTimer + 16);
std::vector<isaac::rooms::SavedLocation> locations;
bool virtualized = true, replica = false, scopeAvailable = true, scoped = false;
unsigned connected = 15, calls = 0, selected = 0, expectedSlot = 1, captureFailure = 0;
int expectedRoom = 84, expectedDimension = 1;
std::string error;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void jump(unsigned rva, void* target) {
    image[rva] = 0xe9;
    field<std::int32_t>(image, rva + 1) =
        reinterpret_cast<Address>(target) - reinterpret_cast<Address>(image + rva + 5);
}
void __attribute__((thiscall)) transition(void* object, int room, int direction, int animation,
                                          void* player, int dimension) {
    require(object == game.data() && room == expectedRoom && direction == -1 && animation == 20 &&
                !player && dimension == expectedDimension && scoped && selected == expectedSlot &&
                field<int>(object, backend::layout::game::leaveDoor) == -1,
            "Certificate return lost its native ABI, destination or borrowed occupant");
    ++calls;
    unsigned control;
    __asm__ __volatile__("stmxcsr %0" : "=m"(control));
    control ^= 0x6000;
    __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0" : : "m"(control) : "xmm7");
}
void prepare() {
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize certificate fixture");
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    const auto begin = backend::entry::deathCertificateReturn;
    // Retain the native boundary's absolute load when MinHook relocates it.
    image[begin] = 0x8b;
    image[begin + 1] = 0x0d;
    field<Address>(image, begin + 2) = reinterpret_cast<Address>(image + backend::globals::game);
    jump(begin + 6, reinterpret_cast<void*>(certificateNative));
    jump(backend::entry::deathCertificateReturnEnd, reinterpret_cast<void*>(certificateDone));
    jump(backend::entry::engineRoomsTransition, reinterpret_cast<void*>(transition));
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
}
void invoke(bool completed) {
    native_fixture::Registers registers{0x11112222, 0x22223333, 0x33334444, 0,
                                        0x44445555, 0x55556666, 0x66667777, 0x77778888};
    const auto result =
        native_fixture::branch(image + backend::entry::deathCertificateReturn, registers);
    require(result.balanced && result.floatingPreserved && !scoped &&
                certificatePath == (completed ? 2u : 1u),
            "Certificate boundary corrupted floating state, stack, scope or continuation");
    for (unsigned i = 0; i < registers.size(); ++i)
        if (i != 3)
            require(result.registers[i] == ((!completed && i == 6)
                                                ? field<Address>(image, backend::globals::game)
                                                : registers[i]),
                    "Certificate boundary corrupted a general register");
    static unsigned originalFlags = result.flags;
    require(result.flags == originalFlags, "Certificate boundary corrupted flags");
}
void install() {
    using isaac::engine::native_certificate_return::install;
    const auto base = reinterpret_cast<Address>(image);
    const auto target = image + backend::entry::deathCertificateReturn;
    require(!install(0), "Missing certificate image accepted");
    require(MH_CreateHook(target, reinterpret_cast<void*>(certificateDone), nullptr) == MH_OK &&
                !install(base) && MH_RemoveHook(target) == MH_OK,
            "Failed certificate install removed another component's hook");
    require(install(base) && install(base) && !install(base + 1),
            "Certificate install did not recover, or accepted a different image");
}
void behavior() {
    invoke(false);
    install();
    locations = {{0, 84, 160, 200}, {2, 103, 200, 280}};
    field<int>(game.data(), backend::layout::game::deathCertificateRoom) = expectedRoom;
    field<signed char>(game.data(), backend::layout::game::deathCertificateDimension) = 1;
    for (unsigned iteration = 1; iteration <= 3; ++iteration) {
        field<int>(game.data(), backend::layout::game::deathCertificateReturnTimer) = 1;
        invoke(true);
        require(calls == iteration &&
                    field<int>(game.data(), backend::layout::game::deathCertificateReturnTimer) ==
                        0,
                "Repeated split-dimension return did not finish its countdown");
    }
    // Native signed dimensions must be extended, and J835's special room
    // resets its dimension before invoking the scoped transition.
    expectedRoom = -2;
#ifdef ISAAC_LAN_TEST_J835
    expectedDimension = 0;
#else
    expectedDimension = -1;
#endif
    field<int>(game.data(), backend::layout::game::deathCertificateRoom) = expectedRoom;
    field<signed char>(game.data(), backend::layout::game::deathCertificateDimension) = -1;
    invoke(true);
    require(calls == 4, "Special-room return was lost");
    for (auto* gate : {&replica, &virtualized}) {
        *gate = !*gate;
        invoke(false);
        *gate = !*gate;
    }
    field<int>(game.data(), backend::layout::game::dimension) = 2;
    invoke(false);
    field<int>(game.data(), backend::layout::game::dimension) = 0;
    field<Address>(image, backend::globals::game) = 0;
    invoke(false);
    field<Address>(image, backend::globals::game) = reinterpret_cast<Address>(game.data());
    connected = 1;
    invoke(true);
    locations.clear();
    connected = 15;
    invoke(true);
    require(calls == 4 && error.empty(), "Native, empty or disconnected return borrowed a player");
    locations = {{0, 84, 160, 200}, {2, 103, 200, 280}, {0, 84, 160, 200}, {2, 103, 200, 280}};
    connected = 9;
    expectedSlot = 3;
    invoke(true);
    require(calls == 5 && selected == 3, "Return selected a disconnected annex occupant");
    scopeAvailable = false;
    invoke(true);
    require(calls == 5 && !error.empty(), "Unavailable annex context did not abort the session");
    scopeAvailable = true;
    for (captureFailure = 1; captureFailure <= 2; ++captureFailure) {
        error.clear();
        invoke(true);
        require(calls == 5 && !error.empty(), "Native boundary leaked a callback exception");
    }
    captureFailure = 0;
    invoke(true);
    require(calls == 6, "Return could not recover after failed context capture");
}
} // namespace
namespace isaac::rooms {
bool virtualized() {
    return ::virtualized;
}
unsigned connected() {
    return ::connected;
}
std::vector<SavedLocation> captureLocations() {
    if (captureFailure == 1)
        throw std::runtime_error("Fixture location capture failure");
    if (captureFailure == 2)
        throw 1;
    return locations;
}
bool withPlayer(unsigned slot, const std::function<void()>& call) {
    if (!scopeAvailable)
        return false;
    selected = slot;
    scoped = true;
    struct Restore {
        ~Restore() {
            scoped = false;
        }
    } restore;
    call();
    return true;
}
} // namespace isaac::rooms
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& value) {
    error = value;
}
} // namespace isaac::runtime
int main() {
    prepare();
    behavior();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release certificate fixture");
}

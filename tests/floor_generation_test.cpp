#include "test_support.h"
#include "native_branch.h"
#include "engine/floor_generation.h"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned challengeOffset = 0x1c319c;
#else
#include "engine/versions/j460/entrypoints.h"
namespace backend = isaac::engine::j460;
constexpr unsigned challengeOffset = 0x26584;
#endif
#include <windows.h>
#include <MinHook.h>
#include <cstring>
#include <map>
#include <vector>

extern "C" {
unsigned floorChoice = 0;
__attribute__((naked)) void floorLarge() {
    __asm__ __volatile__("movl $1, _floorChoice\n\tret");
}
__attribute__((naked)) void floorNormal() {
    __asm__ __volatile__("movl $0, _floorChoice\n\tret");
}
}
namespace {
using Address = std::uintptr_t;
constexpr unsigned comparisonBytes = 7, arithmeticFlags = 0x8d5, equalFlags = 0x44;
std::vector<unsigned char> game(challengeOffset + 16, 0xa5);
unsigned char* image = nullptr;
bool requested = false, throwRequest = false;
std::string error;
const std::array entries{backend::entry::levelLargeFloorCount,
                         backend::entry::levelLargeFloorShape};
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
void jump(unsigned rva, void* target) {
    image[rva] = 0xe9;
    field<std::int32_t>(image, rva + 1) =
        reinterpret_cast<Address>(target) - reinterpret_cast<Address>(image + rva + 5);
}
void prepare() {
    constexpr unsigned imageSize = 0x400000;
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize floor fixture");
    for (unsigned i = 0; i < entries.size(); ++i) {
        const auto entry = entries[i], branch = entry + comparisonBytes;
        std::memset(image + entry, 0x90, 32);
        image[entry] = 0x83;
        image[entry + 1] = 0xb8;
        field<unsigned>(image, entry + 2) = challengeOffset;
        image[entry + 6] = 21;
        // Count uses a near JNE; shape uses a short JNE. Both must survive
        // relocation into the hook's native trampoline.
        if (i == 0) {
            image[branch] = 0x0f;
            image[branch + 1] = 0x85;
            field<int>(image, branch + 2) = 11;
            jump(branch + 6, reinterpret_cast<void*>(floorLarge));
        } else {
            image[branch] = 0x75;
            image[branch + 1] = 15;
            jump(branch + 2, reinterpret_cast<void*>(floorLarge));
        }
        jump(branch + 17, reinterpret_cast<void*>(floorNormal));
    }
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
}
bool largeFloor() {
    unsigned control;
    __asm__ __volatile__("stmxcsr %0" : "=m"(control));
    control ^= 0x6000;
    __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit\n\tldmxcsr %0" : : "m"(control) : "xmm7");
    if (throwRequest)
        throw std::runtime_error("Fixture floor callback failure");
    return requested;
}
native_fixture::BranchResult invoke(unsigned entry, unsigned challenge, bool large) {
    field<unsigned>(game.data(), challengeOffset) = challenge;
    const auto before = game;
    native_fixture::Registers registers{
        0x11112222, 0x22223333, 0x33334444, 0,
        0x44445555, 0x55556666, 0x66667777, reinterpret_cast<Address>(game.data())};
    const auto result = native_fixture::branch(image + entry, registers);
    require(floorChoice == large && result.balanced && result.floatingPreserved && game == before,
            "Floor branch changed native fields, stack or floating state");
    for (unsigned i = 0; i < registers.size(); ++i)
        if (i != 3)
            require(result.registers[i] == registers[i], "Floor gate changed a general register");
    return result;
}
void install() {
    using isaac::engine::installFloorGeneration;
    const auto base = reinterpret_cast<Address>(image);
    require(!installFloorGeneration(0, largeFloor), "Missing floor image accepted");
    for (auto entry : entries) {
        const auto collision = image + entry + comparisonBytes;
        require(MH_CreateHook(collision, reinterpret_cast<void*>(floorNormal), nullptr) == MH_OK,
                "Prepare conflicting floor hook");
        require(!installFloorGeneration(base, largeFloor), "Partial floor install succeeded");
        for (auto other : entries) {
            const auto target = image + other + comparisonBytes;
            const auto result =
                MH_CreateHook(target, reinterpret_cast<void*>(floorNormal), nullptr);
            require(result == (other == entry ? MH_ERROR_ALREADY_CREATED : MH_OK),
                    "Floor rollback retained own hook or removed foreign hook");
            if (other != entry)
                MH_RemoveHook(target);
        }
        require(MH_RemoveHook(collision) == MH_OK, "Remove conflicting floor fixture");
    }
    require(installFloorGeneration(base, largeFloor) && installFloorGeneration(base, largeFloor),
            "Floor hooks did not recover or could not be reused after parent install failure");
    require(!installFloorGeneration(base, nullptr) && !installFloorGeneration(base + 1, largeFloor),
            "Floor hook reuse accepted different configuration");
}
void behavior() {
    constexpr std::array challenges{0u, 20u, 21u, 22u, 0xffffffffu};
    std::map<std::pair<unsigned, unsigned>, unsigned> flags;
    for (auto entry : entries)
        for (auto challenge : challenges)
            flags[{entry, challenge}] = invoke(entry, challenge, challenge == 21).flags;
    install();
    for (auto entry : entries)
        for (auto challenge : challenges)
            for (bool large : {false, true}) {
                requested = large;
                const auto result = invoke(entry, challenge, large || challenge == 21);
                const auto original = flags.at({entry, challenge});
                require(result.flags ==
                            (large ? ((original & ~arithmeticFlags) | equalFlags) : original),
                        "Floor comparison flags changed outside the requested equal branch");
            }
    requested = true;
    throwRequest = true;
    for (auto entry : entries) {
        const auto result = invoke(entry, 22, false);
        require(result.flags == flags.at({entry, 22}) && error == "Fixture floor callback failure",
                "Failed callback changed the native comparison or crossed its stack frame");
    }
}
} // namespace
namespace isaac::runtime {
void abort(const std::string& value) {
    error = value;
}
} // namespace isaac::runtime
int main() {
    prepare();
    behavior();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release floor fixture");
}

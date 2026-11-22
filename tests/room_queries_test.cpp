#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/room_queries.h"
#include <MinHook.h>
#include <array>
#include <cstring>
#include <windows.h>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
constexpr unsigned queryEntry = isaac::engine::j835::entry::playerManagerHasPlayerType;
constexpr bool returnsPointer = false;
#else
#include "engine/versions/j511/entrypoints.h"
constexpr unsigned queryEntry = isaac::engine::j511::entry::playerManagerFindPlayerType;
constexpr bool returnsPointer = true;
#endif

namespace {
namespace queries = isaac::engine::native_room_queries;
using Address = std::uintptr_t;
constexpr unsigned callerEntry = 0x100, queryReturn = callerEntry + 9;
unsigned char* image = nullptr;
int localKind = 7, teamKind = 31;
struct Manager {
    int* active = &localKind;
} manager;
unsigned calls = 0, errors = 0;
bool share = false, nested = false, throwQuery = false;
Address lastCaller = 0;

// Boolean results deliberately retain nonzero high EAX bits. A pointer-shaped
// trampoline would mistake an absent native result for a present player.
__attribute__((naked)) void nativeBoolean() {
    __asm__ __volatile__("movl (%ecx), %edx\n\t"
                         "movl 4(%esp), %eax\n\t"
                         "cmpl (%edx), %eax\n\t"
                         "movl $0x56341200, %eax\n\t"
                         "sete %al\n\tret $4");
}
__attribute__((naked)) void nativePointer() {
    __asm__ __volatile__("movl (%ecx), %eax\n\t"
                         "movl 4(%esp), %edx\n\t"
                         "cmpl (%eax), %edx\n\t"
                         "je 1f\n\txorl %eax, %eax\n1:\tret $4");
}
unsigned invoke(int kind) {
    const auto result =
        native_fixture::call(image + callerEntry, &manager, {static_cast<unsigned>(kind)});
    require(result.balanced && result.preserved, "Character query changed its native ABI");
    return returnsPointer ? result.eax : result.eax & 0xff;
}
void policy(int kind, Address caller, const std::function<void()>& query) {
    ++calls;
    lastCaller = caller;
    struct Restore {
        int* previous = manager.active;
        ~Restore() {
            manager.active = previous;
        }
    } restore;
    if (share && kind == teamKind)
        manager.active = &teamKind;
    if (nested) {
        nested = false;
        require(invoke(localKind) == 0 && manager.active == &teamKind,
                "Nested query lost its outer borrowed roster");
    }
    query();
    if (throwQuery)
        throw std::runtime_error("Character query scope failure");
}
void otherPolicy(int, Address, const std::function<void()>& query) {
    query();
}
void patch(unsigned rva, auto function) {
    image[rva] = 0xe9;
    const auto relative = static_cast<std::int32_t>(reinterpret_cast<Address>(function) -
                                                    reinterpret_cast<Address>(image + rva + 5));
    std::memcpy(image + rva + 1, &relative, sizeof relative);
    std::memset(image + rva + 5, 0x90, 11);
}
void installation() {
    require(!queries::install(0, policy) && !queries::hasType(&manager, localKind),
            "Uninstalled query accepted a native call");
    constexpr unsigned imageSize = 0x600000;
    image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
    require(image && MH_Initialize() == MH_OK, "Initialize query fixture");
    patch(queryEntry, returnsPointer ? nativePointer : nativeBoolean);
    // Forward the incoming thiscall argument from a known image caller.
    const std::array<unsigned char, 12> caller{0xff, 0x74, 0x24, 0x04, 0xe8, 0,
                                               0,    0,    0,    0xc2, 0x04, 0};
    std::memcpy(image + callerEntry, caller.data(), caller.size());
    const auto relative = static_cast<std::int32_t>(queryEntry - queryReturn);
    std::memcpy(image + callerEntry + 5, &relative, sizeof relative);
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    const auto base = reinterpret_cast<Address>(image);
    require(!queries::install(base, nullptr), "Missing query policy accepted");
    require(MH_CreateHook(image + queryEntry, reinterpret_cast<void*>(nativePointer), nullptr) ==
                MH_OK,
            "Prepare foreign query hook");
    require(!queries::install(base, policy) && !queries::hasType(&manager, localKind),
            "Conflicting install retained a callable query");
    require(MH_CreateHook(image + queryEntry, reinterpret_cast<void*>(nativePointer), nullptr) ==
                MH_ERROR_ALREADY_CREATED,
            "Failed install removed a foreign hook");
    require(MH_RemoveHook(image + queryEntry) == MH_OK && queries::install(base, policy),
            "Query install did not recover after a conflict");
    require(queries::install(base, policy) && !queries::install(base, otherPolicy) &&
                !queries::install(base + 1, policy),
            "Query retry changed an installed configuration");
}
void behavior() {
    const auto localResult = returnsPointer ? reinterpret_cast<Address>(&localKind) : 1;
    const auto teamResult = returnsPointer ? reinterpret_cast<Address>(&teamKind) : 1;
    require(invoke(localKind) == localResult && invoke(teamKind) == 0 && calls == 2 &&
                lastCaller == queryReturn,
            "Native result, scope forwarding or caller identity changed");
    require(queries::hasType(&manager, localKind) && !queries::hasType(&manager, teamKind) &&
                !queries::hasType(nullptr, teamKind) && calls == 2,
            "Direct query did not preserve the current scope or reentered the policy");
    share = true;
    require(invoke(teamKind) == teamResult && manager.active == &localKind,
            "Team query did not restore its borrowed roster");
    nested = true;
    require(invoke(teamKind) == teamResult && manager.active == &localKind,
            "Nested native queries changed the outer result");
    throwQuery = true;
    require(invoke(teamKind) == 0 && errors == 1 && manager.active == &localKind,
            "Query exception crossed the native ABI or retained borrowed state");
    throwQuery = false;
    share = false;
    require(invoke(teamKind) == 0 && invoke(localKind) == localResult,
            "Restored room query retained team state");
}
} // namespace
namespace isaac::runtime {
void abort(const std::string&) {
    ++errors;
}
} // namespace isaac::runtime
int main() {
    installation();
    behavior();
    require(MH_Uninitialize() == MH_OK && VirtualFree(image, 0, MEM_RELEASE),
            "Release query fixture");
}

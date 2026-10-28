// Exercise the production x86 boundaries without starting the game.
#include "test_support.h"
#include "engine/versions/common/room_routing.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
constexpr unsigned roomOffset = 0x18194, dimensionOffset = 0x1819c, doorOffset = 0x181ac;
constexpr unsigned seedCursesOffset = 0x1c3170, redirectOffset = 0xf;
#else
#include "engine/versions/j460/entrypoints.h"
namespace backend = isaac::engine::j460;
constexpr unsigned roomOffset = 0x18304, dimensionOffset = 0x1830c, doorOffset = 0x1831c;
constexpr unsigned seedCursesOffset = 0x26550, redirectOffset = 0xb;
#endif
#include <array>
#include <cstdio>
#include <cstring>
#include <utility>
#include <vector>

extern "C" {
unsigned roomBoundaryVisits = 0;
unsigned roomBoundaryECX = 0, roomBoundaryEBX = 0;
unsigned roomBoundarySSE = 0, roomBoundaryFlags = 0, roomBoundaryMXCSR = 0;
double roomBoundaryX87 = 0;
void* roomBoundaryTarget = nullptr;
void* roomMazeTarget = nullptr;
unsigned char roomBoundaryFrame[16]{};
#define CAPTURE_REGISTERS                                                                          \
    "pushfl\n\tpopl _roomBoundaryFlags\n\tmovl %ecx, _roomBoundaryECX\n\t"                         \
    "movl %ebx, _roomBoundaryEBX\n\tmovd %xmm7, _roomBoundarySSE\n\t"                              \
    "fstpl _roomBoundaryX87\n\tstmxcsr _roomBoundaryMXCSR\n\t"
__attribute__((naked)) int roomBoundaryContinue() {
    __asm__ __volatile__(CAPTURE_REGISTERS "incl _roomBoundaryVisits\n\tmovl $17, %eax\n\tret");
}
__attribute__((naked)) int roomBoundaryResident() {
    __asm__ __volatile__(CAPTURE_REGISTERS "movl $23, %eax\n\tret");
}
#undef CAPTURE_REGISTERS
#define INVOKE_BOUNDARY(TARGET)                                                                    \
    "pushl %ebp\n\tmovl $_roomBoundaryFrame, %ebp\n\t"                                             \
    "pushl %ebx\n\tmovl $0x12345678, %ebx\n\t"                                                     \
    "movl $0x87654321, %ecx\n\tpcmpeqd %xmm7, %xmm7\n\tfld1\n\t"                                   \
    "cmpl %eax, %eax\n\tstc\n\tcall *_" #TARGET "\n\t"                                             \
    "popl %ebx\n\tpopl %ebp\n\tret"
__attribute__((naked)) int invokeRoomBoundary() {
    __asm__ __volatile__(INVOKE_BOUNDARY(roomBoundaryTarget));
}
__attribute__((naked)) int invokeMazeBoundary() {
    __asm__ __volatile__(INVOKE_BOUNDARY(roomMazeTarget));
}
#undef INVOKE_BOUNDARY
}
namespace {
unsigned addedCalls = 0, removedCalls = 0;
unsigned __cdecl addedCurses() {
    ++addedCalls;
    return 0x28;
}
unsigned __cdecl removedCurses() {
    ++removedCalls;
    return 0x2;
}
void patch(unsigned char* image, unsigned rva, auto function) {
    std::memset(image + rva, 0x90, 16);
    image[rva] = 0xe9;
    const auto relative = reinterpret_cast<std::uintptr_t>(function) -
                          reinterpret_cast<std::uintptr_t>(image + rva + 5);
    std::memcpy(image + rva + 1, &relative, 4);
}
void preserved(unsigned mxcsr) {
    require(roomBoundaryECX == 0x87654321 && roomBoundaryEBX == 0x12345678 &&
                roomBoundarySSE == 0xffffffff && roomBoundaryX87 == 1 &&
                roomBoundaryMXCSR == mxcsr && (roomBoundaryFlags & 0x41) == 0x41,
            "Room boundary corrupted native integer/flag/SSE/x87 state");
}
} // namespace
int main() {
    try {
        using namespace isaac::engine::native_room_routing;
        require(!installRoomRouting(0) && currentCurses() == 0,
                "Missing image reached native code");
        constexpr unsigned imageSize = 0x890000;
        auto* fakeImage = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(fakeImage && MH_Initialize() == MH_OK, "Allocate native fixture");
        const auto base = reinterpret_cast<std::uintptr_t>(fakeImage);
        std::vector<std::uint8_t> fakeGame(seedCursesOffset + sizeof(int));
        auto& gamePointer = *reinterpret_cast<std::uintptr_t*>(fakeImage + backend::globals::game);
        gamePointer = reinterpret_cast<std::uintptr_t>(fakeGame.data());
        auto field = [&](unsigned offset) -> int& {
            return *reinterpret_cast<int*>(fakeGame.data() + offset);
        };
        field(roomOffset) = 70;
        field(dimensionOffset) = 0;
        field(doorOffset) = 3;
        patch(fakeImage, backend::entry::levelRoomEntryResolved, roomBoundaryContinue);
        patch(fakeImage, backend::entry::levelRoomChangeReturn, roomBoundaryResident);
        patch(fakeImage, backend::entry::levelMazeBranch, roomBoundaryContinue);
        patch(fakeImage, backend::entry::levelMazeBranchEnd, roomBoundaryResident);
        patch(fakeImage, backend::entry::gameAddedSeedCurses, addedCurses);
        patch(fakeImage, backend::entry::gameRemovedSeedCurses, removedCurses);
        FlushInstructionCache(GetCurrentProcess(), fakeImage, imageSize);
        auto* foreign = fakeImage + backend::entry::levelMazeBranch;
        auto* resolved = fakeImage + backend::entry::levelRoomEntryResolved;
        require(MH_CreateHook(foreign, reinterpret_cast<void*>(roomBoundaryResident), nullptr) ==
                    MH_OK,
                "Prepare foreign hook conflict");
        require(!installRoomRouting(base) && !image && !isaac_lan_room_resolved_original &&
                    !isaac_lan_room_maze_original,
                "Failed installation retained partial hooks");
        require(MH_CreateHook(resolved, reinterpret_cast<void*>(roomBoundaryResident), nullptr) ==
                    MH_OK,
                "Failed installation leaked its first hook");
        require(MH_CreateHook(foreign, reinterpret_cast<void*>(roomBoundaryResident), nullptr) ==
                    MH_ERROR_ALREADY_CREATED,
                "Failed installation removed a foreign hook");
        require(MH_RemoveHook(resolved) == MH_OK && MH_RemoveHook(foreign) == MH_OK &&
                    installRoomRouting(base),
                "Room hook installation did not recover");
        require(!installRoomRouting(base), "Duplicate installation replaced original trampolines");
        roomBoundaryTarget = resolved;
        roomMazeTarget = foreign;
        unsigned control;
        __asm__ __volatile__("stmxcsr %0" : "=m"(control));
        field(0xc) = 0x3;
        field(seedCursesOffset) = 0x4;
        require(currentCurses() == 0x2d && addedCalls == 1 && removedCalls == 1,
                "Curses lost base/seed/added bits or ignored removed bits");
        gamePointer = 0;
        require(currentCurses() == 0 && addedCalls == 1 && removedCalls == 1,
                "Missing Game reached native seed queries");
        gamePointer = reinterpret_cast<std::uintptr_t>(fakeGame.data());
        require(invokeRoomBoundary() == 17, "Unmanaged native room entry was intercepted");
        unsigned prepared = 0;
        for (const auto& [fresh, redirected] :
             {std::pair{true, false}, std::pair{true, true}, std::pair{false, false},
              std::pair{false, true}, std::pair{true, false}}) {
            roomBoundaryFrame[redirectOffset] = redirected;
            const auto calls = roomBoundaryVisits;
            withResolvedRoomEntry(
                [&](RoomArrival arrival) {
                    require(arrival.index == 70 && arrival.dimension == 0 && arrival.door == 3 &&
                                arrival.redirected == redirected,
                            "Boundary did not expose the native resolved room and entrance");
                    ++prepared;
                    __asm__ __volatile__("pxor %%xmm7, %%xmm7\n\tfninit" ::: "xmm7");
                    const unsigned altered = control ^ 0x6000;
                    __asm__ __volatile__("ldmxcsr %0" : : "m"(altered));
                    return fresh;
                },
                [&] {
                    require(invokeRoomBoundary() == (fresh ? 17 : 23),
                            "Occupied room ran initialization or fresh room skipped it");
                });
            preserved(control);
            require(roomBoundaryVisits == calls + (fresh ? 1 : 0),
                    "Native destination initialized more than once");
            require(!pending, "Native entry retained a borrowed callback");
        }
        require(prepared == 5, "Room callback was repeated or lost");
        // A rejected nested scope must leave the outer borrowed callback intact.
        withResolvedRoomEntry(
            [&](RoomArrival) {
                bool rejected = false;
                try {
                    withResolvedRoomEntry([](RoomArrival) { return true; }, [] {});
                } catch (const std::runtime_error&) {
                    rejected = true;
                }
                require(rejected, "Nested room resolution was accepted");
                return true;
            },
            [&] { require(invokeRoomBoundary() == 17, "Outer room resolution was lost"); });
        for (bool inside : {false, true}) {
            bool failed = false;
            try {
                withResolvedRoomEntry(
                    [](RoomArrival) -> bool { throw std::runtime_error("entry failed"); },
                    [&] {
                        if (!inside)
                            throw std::runtime_error("native call failed");
                        require(invokeRoomBoundary() == 23,
                                "Callback error crossed native frames or initialized a room");
                    });
            } catch (const std::runtime_error&) {
                failed = true;
            }
            require(failed && !pending && invokeRoomBoundary() == 17,
                    "Failed native entry left a stale callback or changed later calls");
        }
        bool missed = false;
        try {
            withResolvedRoomEntry([](RoomArrival) { return true; }, [] {});
        } catch (const std::runtime_error&) {
            missed = true;
        }
        require(missed && !pending, "Unresolved entry silently committed a requested room");
        gamePointer = 0;
        bool lostGame = false;
        try {
            withResolvedRoomEntry(
                [](RoomArrival) {
                    throw std::runtime_error("Unexpected prepare");
                    return true;
                },
                [&] {
                    require(invokeRoomBoundary() == 23, "Missing Game continued initialization");
                });
        } catch (const std::runtime_error& error) {
            lostGame = std::string(error.what()) == "Native room resolution lost its Game";
        }
        require(lostGame && !pending, "Missing Game lost its failure or retained the callback");
        gamePointer = reinterpret_cast<std::uintptr_t>(fakeGame.data());
        require(invokeMazeBoundary() == 17, "Authority skipped native Maze decisions");
        withoutRoomCurseRouting([&] {
            require(invokeMazeBoundary() == 23, "Fixed destination reran Maze or its room swap");
            withoutRoomCurseRouting(
                [&] { require(invokeMazeBoundary() == 23, "Nested suppression"); });
            require(invokeMazeBoundary() == 23, "Nested call released outer suppression");
        });
        preserved(control);
        require(invokeMazeBoundary() == 17, "Replica suppression leaked into authority");
        try {
            withoutRoomCurseRouting([] { throw std::runtime_error("failed"); });
        } catch (const std::runtime_error&) {
        }
        require(invokeMazeBoundary() == 17, "Failure leaked curse suppression");
        require(MH_Uninitialize() == MH_OK, "Remove fixture hooks");
        VirtualFree(fakeImage, 0, MEM_RELEASE);
        std::puts(
            "PASS native x86 room boundary, occupied entry, register preservation and cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

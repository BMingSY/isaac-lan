// Exercise the production x86 boundaries without starting the game.
#include "test_support.h"
#include "engine/versions/j460/room_routing.cpp"
#include <array>
#include <cstdio>
#include <utility>
#include <vector>

extern "C" {
unsigned roomBoundaryVisits = 0;
unsigned roomBoundaryECX = 0, roomBoundaryEBX = 0;
float roomBoundarySSE = 0;
unsigned char roomBoundaryFrame[16]{};
__attribute__((naked)) int roomBoundaryContinue() {
    __asm__ __volatile__("incl _roomBoundaryVisits\n\tmovl %ecx, _roomBoundaryECX\n\t"
                         "movl %ebx, _roomBoundaryEBX\n\tmovss %xmm7, _roomBoundarySSE\n\t"
                         "movl $17, %eax\n\tret");
}
__attribute__((naked)) int roomBoundaryResident() {
    __asm__ __volatile__("movl $23, %eax\n\tret");
}
__attribute__((naked)) int invokeRoomBoundary() {
    __asm__ __volatile__("pushl %ebp\n\tmovl $_roomBoundaryFrame, %ebp\n\t"
                         "pushl %ebx\n\tmovl $0x12345678, %ebx\n\t"
                         "movl $0x87654321, %ecx\n\tmovl $0x3f400000, %eax\n\t"
                         "movd %eax, %xmm7\n\tcall _isaac_lan_room_resolved_thunk\n\t"
                         "popl %ebx\n\tpopl %ebp\n\tret");
}
__attribute__((naked)) int invokeMazeBoundary() {
    __asm__ __volatile__("call _isaac_lan_room_maze_thunk\n\tret");
}
}
int main() {
    try {
        using namespace isaac::engine::j460;
        std::vector<std::uint8_t> fakeImage(globals::game + sizeof(std::uintptr_t));
        std::vector<std::uint8_t> fakeGame(layout::game::enterDoor + sizeof(int));
        image = reinterpret_cast<std::uintptr_t>(fakeImage.data());
        *reinterpret_cast<std::uintptr_t*>(fakeImage.data() + globals::game) =
            reinterpret_cast<std::uintptr_t>(fakeGame.data());
        auto field = [&](unsigned offset) -> int& {
            return *reinterpret_cast<int*>(fakeGame.data() + offset);
        };
        field(layout::game::roomIndex) = 70;
        field(layout::game::dimension) = 0;
        field(layout::game::enterDoor) = 3;
        isaac_lan_room_resolved_original = reinterpret_cast<void*>(roomBoundaryContinue);
        isaac_lan_room_resolved_return = reinterpret_cast<void*>(roomBoundaryResident);
        isaac_lan_room_maze_original = reinterpret_cast<void*>(roomBoundaryContinue);
        isaac_lan_room_maze_end = reinterpret_cast<void*>(roomBoundaryResident);
        require(invokeRoomBoundary() == 17, "Unmanaged native room entry was intercepted");
        unsigned prepared = 0;
        for (const auto& [fresh, redirected] :
             {std::pair{true, false}, std::pair{true, true}, std::pair{false, false},
              std::pair{false, true}, std::pair{true, false}}) {
            roomBoundaryFrame[layout::roomChangeFrame::mazeRedirected] = redirected;
            const auto calls = roomBoundaryVisits;
            withResolvedRoomEntry(
                [&](RoomArrival arrival) {
                    require(arrival.index == 70 && arrival.dimension == 0 && arrival.door == 3 &&
                                arrival.redirected == redirected,
                            "Boundary did not expose the native resolved room and entrance");
                    ++prepared;
                    __asm__ __volatile__("pxor %%xmm7, %%xmm7" ::: "xmm7");
                    return fresh;
                },
                [&] {
                    require(invokeRoomBoundary() == (fresh ? 17 : 23),
                            "Occupied room ran initialization or fresh room skipped it");
                });
            require(roomBoundaryVisits == calls + (fresh ? 1 : 0),
                    "Native destination initialized more than once");
            require(!pending, "Native entry retained a borrowed callback");
        }
        require(prepared == 5 && roomBoundaryECX == 0x87654321 && roomBoundaryEBX == 0x12345678 &&
                    roomBoundarySSE == 0.75f,
                "Entry callback corrupted native general/SSE registers");
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
        require(invokeMazeBoundary() == 17, "Authority skipped native Maze decisions");
        withoutRoomCurseRouting([&] {
            require(invokeMazeBoundary() == 23, "Fixed destination reran Maze or its room swap");
            withoutRoomCurseRouting(
                [&] { require(invokeMazeBoundary() == 23, "Nested suppression"); });
            require(invokeMazeBoundary() == 23, "Nested call released outer suppression");
        });
        require(invokeMazeBoundary() == 17, "Replica suppression leaked into authority");
        try {
            withoutRoomCurseRouting([] { throw std::runtime_error("failed"); });
        } catch (const std::runtime_error&) {
        }
        require(invokeMazeBoundary() == 17, "Failure leaked curse suppression");
        std::puts(
            "PASS native x86 room boundary, occupied entry, register preservation and cleanup");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

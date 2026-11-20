#include "test_support.h"
#include "engine/versions/common/rooms_bindings.h"
#include <windows.h>
#include <array>
#include <cstring>
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
namespace backend = isaac::engine::j835;
#else
#include "engine/versions/j510/entrypoints.h"
namespace backend = isaac::engine::j510;
#endif

namespace {
using Address = std::uintptr_t;
unsigned visits = 0, movie = 0;
void* observedFamiliar = nullptr;
void* expectedRoom = nullptr;
unsigned priceCalls = 0;
void __attribute__((thiscall)) enterA(void* familiar) {
    observedFamiliar = familiar;
    visits += 1;
}
void __attribute__((thiscall)) enterB(void* familiar) {
    observedFamiliar = familiar;
    visits += 10;
}
#ifdef ISAAC_LAN_TEST_J835
int __attribute__((thiscall)) price(void* room, int variant, int subtype, int shopItem) {
    require(room == expectedRoom && variant == 100 && subtype == 51 && shopItem == 3,
            "Original price query lost its native arguments");
    ++priceCalls;
    return -2;
}
int __attribute__((thiscall)) discount(void* room, int shopItem, int base) {
    require(room == expectedRoom && shopItem == 3 && base == -2,
            "Original discount query lost its base price");
    ++priceCalls;
    return -1;
}
void __stdcall showMovie(unsigned id, bool cleanup) {
    require(!cleanup, "Dogma cinematic unexpectedly requested run cleanup");
    movie = id;
}
#else
int __attribute__((thiscall)) price(void* room, int variant, int subtype, int shopItem,
                                    void* buyer) {
    require(room == expectedRoom && variant == 100 && subtype == 51 && shopItem == 3 && !buyer,
            "Price query changed the borrowed-roster mode");
    ++priceCalls;
    return -2;
}
int __attribute__((thiscall)) discount(void* room, int shopItem, int base, void* buyer) {
    require(room == expectedRoom && shopItem == 3 && base == -2 && !buyer,
            "Discount query lost its base price or changed buyer mode");
    ++priceCalls;
    return -1;
}
void __stdcall showMovie(unsigned id, bool cleanup, unsigned mode) {
    require(!cleanup && mode == 1, "Dogma cinematic changed its native mode");
    movie = id;
}
#endif
void patch(unsigned char* image, unsigned rva, auto function) {
    image[rva] = 0xe9;
    const auto offset = static_cast<std::int32_t>(reinterpret_cast<Address>(function) -
                                                  reinterpret_cast<Address>(image + rva + 5));
    std::memcpy(image + rva + 1, &offset, sizeof offset);
}
} // namespace
int main() {
    const auto& bindings = isaac::engine::native_rooms::bindings;
    constexpr unsigned imageSize = 0x700000;
    auto* image = static_cast<unsigned char*>(
        VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    require(image, "Allocate room binding fixture");
    const auto base = reinterpret_cast<Address>(image);
    patch(image, backend::entry::managerShowCutscene, showMovie);
    patch(image, backend::entry::roomPickupPrice, price);
    patch(image, backend::entry::roomDiscountedPrice, discount);
#ifdef ISAAC_LAN_TEST_J835
    patch(image, backend::entry::familiarNewRoom203, enterA);
    patch(image, backend::entry::familiarNewRoom221, enterB);
#else
    patch(image, backend::entry::engineRoomsRoomCall, enterA);
    (void)enterB;
#endif
    FlushInstructionCache(GetCurrentProcess(), image, imageSize);
    std::array<unsigned char, 64> familiar{};
    std::array<unsigned char, 64> room{};
    expectedRoom = room.data();
    auto& variant = *reinterpret_cast<unsigned*>(familiar.data() + bindings.layout.entity.variant);
    for (unsigned repeat = 0; repeat < 100; ++repeat) {
        variant = 203;
        bindings.familiarNewRoom(base, reinterpret_cast<Address>(familiar.data()));
        require(observedFamiliar == familiar.data(), "Room entry lost its familiar receiver");
        variant = 221;
        bindings.familiarNewRoom(base, reinterpret_cast<Address>(familiar.data()));
        variant = 202;
        bindings.familiarNewRoom(base, reinterpret_cast<Address>(familiar.data()));
        bindings.beginDogmaCinematic(base);
        require(bindings.pickupPrice(base, reinterpret_cast<Address>(room.data()), 100, 51, 3) ==
                    -1,
                "Room price adapter lost the native discounted price");
    }
#ifdef ISAAC_LAN_TEST_J835
    require(visits == 1100, "Original inline room entry dispatched the wrong familiar");
#else
    require(visits == 300, "Native familiar room entry was not forwarded");
#endif
    require(movie == 25, "Dogma requested the wrong native cinematic");
    require(priceCalls == 200, "Room price skipped a native query");
    require(VirtualFree(image, 0, MEM_RELEASE), "Release room binding fixture");
}

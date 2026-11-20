#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/grid_state.cpp"
#include <array>
#include <cstring>
#include <iostream>
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned gameGlobal = 0x7fd65c, gameRoom = 0x18190, railOffset = 0x7350;
constexpr unsigned extraSprite = 0x164, removeEntry = 0x3d9b00, makeEntry = 0x3ad410;
#else
#include "engine/versions/j510/entrypoints.h"
constexpr unsigned gameGlobal = isaac::engine::j510::globals::game, gameRoom = 0x18300;
constexpr unsigned railOffset = 0x7484, extraSprite = 0x27c;
constexpr unsigned removeEntry = isaac::engine::j510::entry::roomRemoveGridEntityImmediate;
constexpr unsigned makeEntry = 0x3f6e60;
#endif
struct lua_State {
    int top = 0;
    std::array<long long, 4> integers{};
    std::array<std::array<std::uintptr_t, 2>, 4> wrappers{};
    std::array<std::size_t, 4> sizes{8, 8, 8, 8};
    std::array<std::uintptr_t, 2> returned{};
    bool success = false, metatable = false;
    std::string input, output;
};
namespace {
namespace grid = isaac::engine::native_grid;
using Address = std::uintptr_t;
bool replica = false, makeSucceeds = true;
unsigned removals = 0, creations = 0;
void* lastReceiver = nullptr;
std::string lastError;
std::array<unsigned char, 0x400> createdDoor;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* value) {
    return reinterpret_cast<Address>(value);
}
void patch(unsigned char* image, unsigned rva, void* target) {
    image[rva] = 0xe9;
    const auto displacement = address(target) - address(image + rva + 5);
    std::memcpy(image + rva + 1, &displacement, 4);
}
void __attribute__((fastcall)) removeNative(void* room, void*, int index, int data, bool keepRock) {
    require(index >= 0 && index < 448 && data == 0 && !keepRock,
            "Immediate removal ABI/arguments changed");
    lastReceiver = room;
    const auto current = field<Address>(room, 0x24 + index * 4);
    if (current) {
        field<Address>(room, 0x24 + index * 4) = 0;
        ++removals;
    }
}
bool __attribute__((fastcall)) makeNative(void* room, void*, int slot) {
    require(slot >= 0 && slot < 8, "MakeDoor slot/ABI changed");
    lastReceiver = room;
    const auto index = field<unsigned>(room, 0x744 + slot * 4);
    require(index < 448, "MakeDoor received an unvalidated grid index");
    if (!makeSucceeds || field<Address>(room, 0x724 + slot * 4))
        return false;
    ++creations;
    createdDoor.fill(0xa5);
    field<unsigned>(createdDoor.data(), 4) = 16;
    field<unsigned>(createdDoor.data(), 0x24) = index;
    field<Address>(room, 0x24 + index * 4) = address(createdDoor.data());
    field<Address>(room, 0x724 + slot * 4) = address(createdDoor.data());
    return true;
}
void configureLua() {
    grid::lua.getTop = [](lua_State* L) { return L->top; };
    grid::lua.toUserdata = [](lua_State* L, int n) -> void* { return L->wrappers.at(n).data(); };
    grid::lua.rawLength = [](lua_State* L, int n) { return L->sizes.at(n); };
    grid::lua.newUserdata = [](lua_State* L, std::size_t size) -> void* {
        require(size == 8, "Door Sprite must be borrowed");
        return L->returned.data();
    };
    grid::lua.checkInteger = [](lua_State* L, int n) { return L->integers.at(n); };
    grid::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    grid::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
    grid::lua.pushLString = [](lua_State* L, const char* value, std::size_t size) -> const char* {
        L->output.assign(value, size);
        return L->output.c_str();
    };
    grid::lua.getMetatable = [](lua_State*, int index) {
        require(index == 1, "Door Sprite metatable source changed");
        return 1;
    };
    grid::lua.setMetatable = [](lua_State* L, int index) {
        require(index == -2, "Door Sprite metatable target changed");
        L->metatable = true;
        return 1;
    };
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& message) {
    lastError = message;
}
} // namespace isaac::runtime
int main() {
    try {
        configureLua();
        constexpr unsigned imageSize = gameGlobal + 4096;
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate grid native fixture image");
        patch(image, removeEntry, reinterpret_cast<void*>(removeNative));
        patch(image, makeEntry, reinterpret_cast<void*>(makeNative));
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        grid::image = address(image);
        std::array<unsigned char, 0x18400> game{};
        std::array<unsigned char, 0x7900> room, otherRoom;
        room.fill(0xa5);
        otherRoom.fill(0x5a);
        auto init = [](auto& value) {
            field<unsigned>(value.data(), 0xc) = 15;
            field<unsigned>(value.data(), 0x10) = 9;
            field<Address>(value.data(), railOffset - 4) = address(value.data());
            for (unsigned i = 0; i < 448; ++i)
                field<Address>(value.data(), 0x24 + i * 4) = 0;
            for (unsigned i = 0; i < 8; ++i) {
                field<Address>(value.data(), 0x724 + i * 4) = 0;
                field<int>(value.data(), 0x744 + i * 4) = -1;
            }
            std::memset(value.data() + railOffset, 255, 448);
        };
        init(room);
        init(otherRoom);
        field<Address>(image, gameGlobal) = address(game.data());
        field<Address>(game.data(), gameRoom) = address(room.data());
        lua_State capture;
        require(grid::roomRails(&capture) == 1 && capture.output == std::string(448, '\xff'),
                "Rail capture read outside its version's grid");
        auto railPacket = capture.output;
        railPacket[17] = 0;
        railPacket[18] = 64;
        railPacket[19] = 82;
        railPacket[20] = static_cast<char>(160);
        const auto beforeRails = room;
        lua_State rails;
        rails.top = 1;
        rails.input = railPacket;
        grid::roomRails(&rails);
        require(!rails.success && room == beforeRails, "Authority accepted rail changes");
        replica = true;
        grid::roomRails(&rails);
        require(rails.success, "Valid room rails rejected");
        auto expected = beforeRails;
        std::memcpy(expected.data() + railOffset, railPacket.data(), 448);
        require(room == expected, "Rail restore changed its owner, Sprite or adjacent fields");
        grid::roomRails(&rails);
        require(rails.success && room == expected, "Repeated rails changed resources");
        for (unsigned length : {0u, 447u, 449u}) {
            rails.input.assign(length, '\xff');
            grid::roomRails(&rails);
            require(!rails.success && room == expected,
                    "Invalid rail length partially changed the room");
        }
        rails.input = railPacket;
        rails.input.back() = static_cast<char>(254);
        grid::roomRails(&rails);
        require(!rails.success && room == expected,
                "Invalid final rail partially changed the room");
        rails.input = railPacket;
        field<Address>(room.data(), railOffset - 4) = address(otherRoom.data());
        const auto wrongOwner = room;
        grid::roomRails(&rails);
        require(!rails.success && room == wrongOwner, "Wrong RailManager owner accepted");
        field<Address>(room.data(), railOffset - 4) = address(room.data());
        field<Address>(game.data(), gameRoom) = address(otherRoom.data());
        rails.input.assign(448, '\xff');
        grid::roomRails(&rails);
        require(rails.success && room == expected,
                "Room switch reused the previous room's rail pointer");
        field<Address>(game.data(), gameRoom) = address(room.data());

        std::array<unsigned char, 0x400> door;
        door.fill(0xa5);
        field<unsigned>(door.data(), 4) = 16;
        field<unsigned>(door.data(), 0x24) = 17;
        field<Address>(room.data(), 0x24 + 17 * 4) = address(door.data());
        lua_State sprite;
        sprite.top = 1;
        sprite.wrappers[1] = {0x12345678, address(door.data()) + 0x40};
        const auto doorBefore = door;
        grid::doorSprite(&sprite);
        require(sprite.returned ==
                        std::array<Address, 2>{0x12345678, address(door.data()) + extraSprite} &&
                    sprite.metatable && door == doorBefore,
                "Door ExtraSprite was copied, owned, or read at another version's offset");
        for (auto size : {0u, 4u, 0x11cu}) {
            sprite.sizes[1] = size;
            sprite.returned = {};
            grid::doorSprite(&sprite);
            require(!sprite.success && sprite.returned == std::array<Address, 2>{},
                    "Malformed or owning grid Sprite accepted");
        }
        sprite.sizes[1] = 8;
        field<unsigned>(door.data(), 4) = 2;
        sprite.returned = {};
        grid::doorSprite(&sprite);
        require(!sprite.success && sprite.returned == std::array<Address, 2>{},
                "ExtraSprite accepted a nondoor allocation");
        field<unsigned>(door.data(), 4) = 16;
        lua_State variant = sprite;
        variant.top = 2;
        variant.integers[2] = -100;
        replica = false;
        grid::gridVariant(&variant);
        require(!variant.success && door == doorBefore, "Authority changed a grid variant");
        replica = true;
        grid::gridVariant(&variant);
        require(variant.success && field<int>(door.data(), 8) == -100,
                "Door signed variant was not restored");
        auto variantExpected = doorBefore;
        field<int>(variantExpected.data(), 8) = -100;
        require(door == variantExpected, "Variant write changed native ownership or Sprite bytes");
        variant.integers[2] = 0x100000000LL;
        grid::gridVariant(&variant);
        require(!variant.success && door == variantExpected,
                "Oversized variant narrowed into native memory");

        lua_State slot;
        slot.top = 3;
        slot.integers[1] = 2;
        slot.integers[2] = 17;
        slot.wrappers[3] = {0x12345678, address(door.data()) + 0x40};
        grid::doorSlot(&slot);
        require(slot.success &&
                    field<Address>(room.data(), 0x724 + 2 * 4) == address(door.data()) &&
                    field<unsigned>(room.data(), 0x744 + 2 * 4) == 17 && creations == 0,
                "Existing door was allocated again or not registered");
        const auto linked = room;
        grid::doorSlot(&slot);
        require(slot.success && room == linked && door == variantExpected,
                "Repeated door registration changed ownership");
        slot.integers[2] = 18;
        grid::doorSlot(&slot);
        require(!slot.success && room == linked, "Wrong door index partially changed the slot");
        slot.integers[2] = 17;
        field<Address>(game.data(), gameRoom) = address(otherRoom.data());
        const auto otherBefore = otherRoom;
        grid::doorSlot(&slot);
        require(!slot.success && otherRoom == otherBefore,
                "Door from another room was borrowed into this room");
        field<Address>(game.data(), gameRoom) = address(room.data());
        lua_State detach;
        detach.top = 1;
        detach.integers[1] = -1;
        grid::doorSlot(&detach);
        require(detach.success &&
                    field<Address>(room.data(), 0x24 + 17 * 4) == address(door.data()) &&
                    door == variantExpected,
                "Clearing borrowed slots destroyed the grid allocation");
        for (unsigned i = 0; i < 8; ++i)
            require(field<Address>(room.data(), 0x724 + i * 4) == 0, "Door detach missed a slot");
        lua_State remove;
        remove.top = 1;
        remove.integers[1] = 17;
        grid::removeGrid(&remove);
        require(remove.success && removals == 1 &&
                    field<Address>(room.data(), 0x24 + 17 * 4) == 0 && lastReceiver == room.data(),
                "Grid removal was deferred or used the wrong room");
        lua_State make;
        make.top = 2;
        make.integers[1] = 2;
        make.integers[2] = 17;
        grid::doorSlot(&make);
        require(make.success && creations == 1 &&
                    field<Address>(room.data(), 0x24 + 17 * 4) == address(createdDoor.data()),
                "Native door creation did not replace the removed grid");
        const auto created = room;
        make.integers[2] = 18;
        grid::doorSlot(&make);
        require(!make.success && room == created && creations == 1,
                "Failed door creation left a partially changed destination");
        for (auto invalid : {-2, 8}) {
            make.integers[1] = invalid;
            grid::doorSlot(&make);
            require(!make.success && room == created, "Invalid door slot reached the native call");
        }
        make.integers[1] = 3;
        make.integers[2] = 448;
        grid::doorSlot(&make);
        require(!make.success && room == created, "Invalid destination reached MakeDoor");
        const auto removeAbi = native_fixture::call(image + removeEntry, room.data(), {17, 0, 0});
        require(removeAbi.balanced && removeAbi.preserved && removals == 2,
                "Immediate removal did not preserve thiscall stack/registers");
        field<Address>(room.data(), 0x724 + 2 * 4) = 0;
        const auto makeAbi = native_fixture::call(image + makeEntry, room.data(), {2});
        require(makeAbi.balanced && makeAbi.preserved && (makeAbi.eax & 255) == 1 && creations == 2,
                "MakeDoor did not preserve thiscall stack/registers or bool return");
        field<Address>(image, gameGlobal) = 0;
        const auto callsBefore = removals + creations;
        grid::removeGrid(&remove);
        grid::doorSlot(&make);
        grid::roomRails(&rails);
        require(!remove.success && !make.success && !rails.success &&
                    callsBefore == removals + creations,
                "Released Game reached native grid methods");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout
            << "Grid layouts, rails, borrowed door ownership, replacement and native ABI passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

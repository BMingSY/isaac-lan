#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/references.cpp"
#include <cstring>
#include <iostream>
#include <map>
#include <set>
#include <vector>
#ifdef ISAAC_LAN_TEST_J835
constexpr unsigned spriteOffset = 0x3c, cartOffset = 0x32c, heldOffset = 0x1358,
                   bombsOffset = 0xb40;
constexpr unsigned assignEntry = 0x28cf00, resizeEntry = 0x3da10;
#else
#include "engine/versions/j511/entrypoints.h"
constexpr unsigned spriteOffset = 0x48, cartOffset = 0x3d4, heldOffset = 0x1414,
                   bombsOffset = 0xbf0;
constexpr unsigned assignEntry = isaac::engine::j511::entry::entityPtrAssign, resizeEntry = 0x50010;
#endif
struct lua_State {
    int top = 1;
    std::array<std::array<std::uintptr_t, 2>, 5> wrappers{};
    std::array<bool, 5> absent{};
    std::array<std::size_t, 5> sizes{8, 8, 8, 8, 8};
    std::vector<long long> values;
    bool success = false;
};
namespace {
namespace refs = isaac::engine::native_references;
using Address = std::uintptr_t;
bool replica = false;
unsigned writes = 0, resizes = 0;
std::map<Address, std::set<Address>> observers;
std::array<Address, 8> map{};
std::array<std::array<Address, 4>, 8> blocks{};
void* resized = nullptr;
std::string lastError;
template <class T> T& field(void* p, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(p) + offset);
}
Address address(const void* p) {
    return reinterpret_cast<Address>(p);
}
void __attribute__((fastcall)) assignNative(void* pointer, void* object) {
    auto& previous = field<Address>(pointer, 0);
    if (previous)
        observers[previous].erase(address(pointer));
    previous = address(object);
    if (previous)
        observers[previous].insert(address(pointer));
    ++writes;
}
void __attribute__((fastcall)) resizeNative(void* deque, void*, unsigned count) {
    require(count == 2 || count == 3, "Native resize count/ABI changed");
    require(field<unsigned>(deque, 16) == 0, "Fixture resize must not transfer an owned deque");
    resized = deque;
    ++resizes;
    for (unsigned i = 0; i < 8; ++i)
        map[i] = address(blocks[i].data());
    field<Address>(deque, 4) = address(map.data());
    field<unsigned>(deque, 8) = 8;
    field<unsigned>(deque, 12) = 31;
    field<unsigned>(deque, 16) = count;
}
void removeEntity(void* object) {
    for (auto pointer : observers[address(object)])
        field<Address>(reinterpret_cast<void*>(pointer), 0) = 0;
    observers.erase(address(object));
}
void patch(unsigned char* image, unsigned rva, void* target) {
    image[rva] = 0xe9;
    auto delta = address(target) - address(image + rva + 5);
    std::memcpy(image + rva + 1, &delta, 4);
}
void configureLua() {
    refs::lua.getTop = [](lua_State* L) { return L->top; };
    refs::lua.type = [](lua_State* L, int n) { return L->absent.at(n) ? 1 : 7; };
    refs::lua.toBoolean = [](lua_State*, int) { return 0; };
    refs::lua.toUserdata = [](lua_State* L, int n) -> void* {
        return L->absent.at(n) ? nullptr : L->wrappers.at(n).data();
    };
    refs::lua.rawLength = [](lua_State* L, int n) { return L->sizes.at(n); };
    refs::lua.pushBoolean = [](lua_State* L, int v) { L->success = v; };
    refs::lua.pushInteger = [](lua_State* L, long long v) { L->values.push_back(v); };
}
void argument(lua_State& L, int slot, void* object) {
    L.absent[slot] = !object;
    L.wrappers[slot] = {0x87654321, object ? address(object) + spriteOffset : 0};
}
} // namespace
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& reason) {
    lastError = reason;
}
} // namespace isaac::runtime
int main() {
    try {
        configureLua();
        constexpr unsigned imageSize = 0x500000;
        auto* image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate references ABI fixture");
        patch(image, assignEntry, reinterpret_cast<void*>(assignNative));
        patch(image, resizeEntry, reinterpret_cast<void*>(resizeNative));
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        refs::image = address(image);
        std::array<unsigned char, 0x1500> player{};
        std::array<std::array<unsigned char, 0x410>, 3> targets{};
        field<unsigned>(player.data(), 0x28) = 1;
        for (unsigned i = 0; i < 3; ++i) {
            field<unsigned>(targets[i].data(), 0x28) = 965;
            field<int>(targets[i].data(), 0x20) = 71 + i;
        }
        lua_State L;
        argument(L, 1, player.data());
        argument(L, 2, targets[0].data());
        L.top = 2;
        const auto playerBefore = player;
        refs::entityMinecart(&L);
        require(!L.success && writes == 0 && player == playerBefore,
                "Authority assigned a minecart");
        replica = true;
        refs::entityMinecart(&L);
        require(
            L.success && field<Address>(player.data(), cartOffset) == address(targets[0].data()) &&
                observers[address(targets[0].data())].contains(address(player.data()) + cartOffset),
            "Minecart did not use native ECX/EDX reference registration");
        refs::entityMinecart(&L);
        require(writes == 1, "Repeated minecart snapshot relinked");
        L.top = 1;
        L.values.clear();
        refs::entityMinecart(&L);
        require(L.values == std::vector<long long>{71},
                "Minecart capture returned a pointer or wrong index");
        L.top = 2;
        argument(L, 2, targets[1].data());
        refs::entityMinecart(&L);
        require(L.success && observers[address(targets[0].data())].empty(),
                "Minecart replacement retained its old observer");
        removeEntity(targets[1].data());
        require(field<Address>(player.data(), cartOffset) == 0,
                "Removed minecart left a dangling pointer");
        argument(L, 2, nullptr);
        refs::entityMinecart(&L);
        require(L.success && writes == 2, "Empty minecart snapshot created a reference");
        argument(L, 2, targets[0].data());
        field<unsigned>(targets[0].data(), 0x28) = 4;
        refs::entityMinecart(&L);
        require(!L.success && writes == 2, "Non-minecart target reached the native assignment");
        for (auto size : {4u, 0x11cu}) {
            L.sizes[1] = size;
            refs::actorHeldEntity(&L);
            require(!L.success && writes == 2,
                    "Invalid owner wrapper reached held-object assignment");
        }
        L.sizes[1] = 8;
        refs::actorHeldEntity(&L);
        require(L.success &&
                    field<Address>(player.data(), heldOffset) == address(targets[0].data()),
                "Held entity wrote the wrong version field");
        refs::actorHeldEntity(&L);
        require(writes == 3, "Repeated held object relinked");
        const auto linked = player;
        argument(L, 2, player.data());
        refs::actorHeldEntity(&L);
        require(!L.success && player == linked, "Self carry partially changed the player");
        removeEntity(targets[0].data());
        require(field<Address>(player.data(), heldOffset) == 0,
                "Held entity deletion did not clear its observer");
        argument(L, 2, nullptr);
        refs::actorHeldEntity(&L);
        require(L.success && writes == 3, "Empty held state recreated a reference");
        require(player == playerBefore, "Reference cleanup changed unrelated player fields");

        for (unsigned type : {906u, 920u}) {
            player.fill(0);
            field<unsigned>(player.data(), 0x28) = type;
            map = {};
            blocks = {};
            observers.clear();
            resizes = 0;
            writes = 0;
            const unsigned slots = type == 906 ? 2 : 3;
            lua_State bombs;
            argument(bombs, 1, player.data());
            refs::bossHeldBombs(&bombs);
            require(bombs.values == std::vector<long long>(slots, -1),
                    "Empty Boss capture touched an unallocated deque");
            bombs.top = slots + 1;
            for (unsigned i = 0; i < slots; ++i)
                argument(bombs, i + 2, nullptr);
            replica = false;
            refs::bossHeldBombs(&bombs);
            require(!bombs.success && resizes == 0, "Authority resized Boss links");
            replica = true;
            refs::bossHeldBombs(&bombs);
            require(bombs.success && resizes == 1 && resized == player.data() + bombsOffset &&
                        writes == 0,
                    "Empty Boss state did not initialize its native render slots");
            for (unsigned i = 0; i < slots; ++i) {
                field<unsigned>(targets[i].data(), 0x28) = 4;
                argument(bombs, i + 2, targets[i].data());
            }
            refs::bossHeldBombs(&bombs);
            require(bombs.success && writes == slots &&
                        field<Address>(blocks[7].data(), 12) == address(targets[0].data()) &&
                        blocks[0][0] == address(targets[1].data()),
                    "Wrapped held-bomb deque used the wrong native layout");
            refs::bossHeldBombs(&bombs);
            require(writes == slots && resizes == 1,
                    "Repeated Boss state changed native ownership");
            const auto beforeInvalid = blocks;
            field<unsigned>(targets[slots - 1].data(), 0x28) = 1;
            refs::bossHeldBombs(&bombs);
            require(!bombs.success && blocks == beforeInvalid && writes == slots,
                    "Invalid last bomb partially assigned earlier slots");
            field<unsigned>(targets[slots - 1].data(), 0x28) = 4;
            removeEntity(targets[0].data());
            require(blocks[7][3] == 0, "Bomb deletion left a dangling registered slot");
            bombs.top = 1;
            bombs.values.clear();
            refs::bossHeldBombs(&bombs);
            std::vector<long long> expected{-1, 72};
            if (slots == 3)
                expected.push_back(73);
            require(bombs.values == expected, "Boss capture did not reflect native deletion");
            bombs.top = slots + 1;
            for (unsigned i = 0; i < slots; ++i)
                argument(bombs, i + 2, nullptr);
            refs::bossHeldBombs(&bombs);
            require(bombs.success, "Room cleanup failed to clear Boss links");
            for (const auto& [target, registered] : observers)
                require(registered.empty(), "Room cleanup retained an EntityPtr observer");
            field<unsigned>(player.data() + bombsOffset, 16) = 0;
            const auto abi =
                native_fixture::call(image + resizeEntry, player.data() + bombsOffset, {slots});
            require(abi.balanced && abi.preserved && resized == player.data() + bombsOffset,
                    "Boss resize violated thiscall receiver/stack/registers");
        }
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout
            << "Native reference bindings, Lua authority, observer cleanup and deque ABI passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

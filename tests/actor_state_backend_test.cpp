#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/actor_state.cpp"
#include <cstring>
#include <iostream>
#include <memory>
#ifdef ISAAC_LAN_TEST_REPENTANCE
constexpr unsigned gameGlobal = 0x7fd65c, getHudEntry = 0x127c0, spriteOffset = 0x3c;
constexpr unsigned typeOffset = 0x130c, costumesOffset = 0x1170, chargesOffset = 0x6a8;
constexpr unsigned pocketsOffset = 0x16c8, bagOffset = 0x1e44, previewOffset = 0x1e4c;
constexpr unsigned poopMana = 0x1e50, poopQueue = 0x1e54, hudStride = 0x6b0, bagDirty = 0x6a1;
constexpr std::array<unsigned, 3> spriteOffsets{0x36c, 0xf48, 0xe34};
#else
constexpr unsigned gameGlobal = 0x8994f8, getHudEntry = 0x18de0, spriteOffset = 0x48;
constexpr unsigned typeOffset = 0x13c4, costumesOffset = 0x1220, chargesOffset = 0x758;
constexpr unsigned pocketsOffset = 0x17a0, bagOffset = 0x1f44, previewOffset = 0x1f4c;
constexpr unsigned poopMana = 0x1f54, poopQueue = 0x1f58, hudStride = 0x6dc, bagDirty = 0x6ad;
constexpr std::array<unsigned, 3> spriteOffsets{0x41c, 0xff8, 0xee4};
#endif
struct lua_State {
    isaac::lua::Function crimeView = nullptr;
    int top = 1;
    std::size_t userdataBytes = 8;
    bool validWrapper = true, success = false, metatable = false, appliedMeta = false;
    long long index = 0;
    std::array<std::uintptr_t, 2> wrapper{};
    std::string input, output;
    std::vector<std::unique_ptr<std::array<std::uintptr_t, 2>>> wrappers;
    unsigned arraySize = 0, inserted = 0;
};
namespace {
namespace state = isaac::engine::native_actor_state;
using Address = std::uintptr_t;
bool replica = false;
bool crimeReady = true;
unsigned hudCalls = 0;
void* currentGame = nullptr;
void* currentHud = nullptr;
std::string error;
std::vector<Address> localPlayers, teamPlayers;
std::vector<bool> rosterQueries;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* object) {
    return reinterpret_cast<Address>(object);
}
void* __attribute__((fastcall)) getHud(void* game, void*) {
    require(game == currentGame, "Crafting bag queried another Game's HUD");
    ++hudCalls;
    return currentHud;
}
std::string bytes(const char* hex) {
    std::string value(hex), result;
    for (unsigned i = 0; i < value.size(); i += 2)
        result += static_cast<char>(std::stoul(value.substr(i, 2), nullptr, 16));
    return result;
}
void configure() {
    state::lua.getTop = [](lua_State* L) { return L->top; };
    state::lua.checkInteger = [](lua_State* L, int) { return L->index; };
    state::lua.toUserdata = [](lua_State* L, int) -> void* {
        return L->validWrapper ? L->wrapper.data() : nullptr;
    };
    state::lua.rawLength = [](lua_State* L, int) { return L->userdataBytes; };
    state::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    state::lua.pushLString = [](lua_State* L, const char* value, std::size_t size) -> const char* {
        L->output.assign(value, size);
        return L->output.c_str();
    };
    state::lua.pushBoolean = [](lua_State* L, int value) { L->success = value; };
    state::lua.createTable = [](lua_State* L, int size, int hash) {
        require(hash == 0 && size >= 0, "Sprite table layout changed");
        L->arraySize = size;
    };
    state::lua.newUserdata = [](lua_State* L, std::size_t size) -> void* {
        require(size == 8, "Sprite wrapper took ownership of native ANM2");
        L->wrappers.push_back(std::make_unique<std::array<Address, 2>>());
        return L->wrappers.back()->data();
    };
    state::lua.getMetatable = [](lua_State* L, int index) {
        require(index == 2, "Sprite metatable source changed");
        L->metatable = true;
        return 1;
    };
    state::lua.setMetatable = [](lua_State* L, int index) {
        require(index == -2 && L->metatable, "Borrowed Sprite lost native destructor metadata");
        L->metatable = false;
        L->appliedMeta = true;
        return 1;
    };
    state::lua.rawSetI = [](lua_State* L, int table, long long index) {
        require(table == -2 && index == L->inserted + 1 && L->appliedMeta,
                "Sprite order or metatable changed");
        L->appliedMeta = false;
        ++L->inserted;
    };
    state::context.roster = [](bool team) {
        rosterQueries.push_back(team);
        return team ? teamPlayers : localPlayers;
    };
}
struct Player {
    std::array<unsigned char, 0x2200> data;
    std::array<unsigned char, 0x260> costumes{};
    Player() {
        data.fill(0xa5);
        field<unsigned>(data.data(), 0x28) = 1;
        field<int>(data.data(), typeOffset) = 25;
        field<Address>(data.data(), costumesOffset) = address(costumes.data());
        field<Address>(data.data(), costumesOffset + 4) =
            address(costumes.data() + costumes.size());
        field<Address>(data.data(), costumesOffset + 8) =
            address(costumes.data() + costumes.size());
    }
};
lua_State invoke(Player& player, int (*function)(lua_State*), const std::string* input = nullptr) {
    lua_State L;
    L.wrapper = {0x12345678, address(player.data.data()) + spriteOffset};
    if (input) {
        L.top = 2;
        L.input = *input;
    }
    error.clear();
    require(function(&L) == 1, "Actor state return count changed");
    return L;
}
void rejection(Player& player, int (*function)(lua_State*), const std::string& input) {
    const auto before = player.data;
    require(!invoke(player, function, &input).success && player.data == before,
            "Invalid actor snapshot partially wrote state");
}
void checkCrimeView(unsigned char* image) {
    lua_State L;
    state::lua.pushClosure = [](lua_State* L, isaac::lua::Function f, int) { L->crimeView = f; };
    state::lua.setField = [](lua_State*, int, const char* name) {
        require(std::string_view(name) == "crime_view", "Unexpected crime view binding");
    };
    state::bindCrimeView(&L, state::lua, address(image), state::context);
#ifdef ISAAC_LAN_TEST_REPENTANCE
    require(!L.crimeView, "Base game registered an unavailable crime mode");
#else
    require(L.crimeView, "Crime mode view is missing");
    std::vector<unsigned char> game(0x26b00, 0), host(0x2f30, 0), guest(0x2f30, 0);
    field<Address>(image, gameGlobal) = address(game.data());
    teamPlayers = {address(host.data()), address(guest.data())};
    localPlayers = {address(guest.data())};
    host[0x28] = guest[0x28] = 1;
    host[0x161c] = 1;
    guest[0x161c] = 2;
    L.top = 0;
    require(L.crimeView(&L) == 1 && !L.success && L.output.empty(), "Read outside crime mode");
    game[0x26644] = 1;
    const auto empty = bytes("0000000000000000"
                             "0100ff0060000000000000"
                             "0200ff0060000000000000");
    const auto armed = bytes("40600000fffffff6"
                             "0101000060000000000000"
                             "0203010060000b00000000");
    host[0x2f14] = guest[0x2f14] = 0xff;
    host[0x2f08] = guest[0x2f08] = 96;
    require(L.crimeView(&L) == 1 && L.output == empty, "Split-room capture lost an actor");
    L.top = 1;
    L.input = armed;
    replica = false;
    require(L.crimeView(&L) == 1 && !L.success, "Authority accepted a crime view");
    replica = true;
    auto reject = [&](const std::string& bad) {
        L.input = bad;
        require(L.crimeView(&L) == 1 && !L.success, "Invalid crime view applied");
    };
    reject(armed.substr(0, armed.size() - 1));
    reject(armed + 'x');
    constexpr unsigned guestRecord = 8 + 11;
    reject(std::string(armed).replace(guestRecord, 1, bytes("01")));       // Wrong controller.
    reject(std::string(armed).replace(guestRecord + 2, 1, bytes("03")));   // Unowned gun.
    reject(std::string(armed).replace(guestRecord + 5, 2, bytes("ffff"))); // Negative ammo.
    reject(std::string(armed).replace(0, 4, bytes("7fc00000"))); // Nonfinite wanted level.
    L.top = 0;
    require(L.crimeView(&L) == 1 && L.output == empty, "Invalid crime view partially wrote state");
    L.top = 1;
    L.input = armed;
    for (int i = 0; i < 2; ++i)
        require(L.crimeView(&L) == 1 && L.success, "Valid or repeated crime view rejected");
    require(field<float>(game.data(), 0x26648) == 3.5f && field<int>(game.data(), 0x26ac0) == -10 &&
                host[0x2f10] == 1 && host[0x2f14] == 0 && guest[0x2f10] == 3 &&
                guest[0x2f14] == 1 && guest[0x2f0a] == 11,
            "Crime view wrote the wrong HUD fields or actor");
    L.top = 0;
    require(L.crimeView(&L) == 1 && L.output == armed, "Crime view failed to round-trip");
    crimeReady = false;
    L.top = 1;
    L.input = empty;
    require(L.crimeView(&L) == 1 && !L.success && guest[0x2f10] == 3,
            "Crime view wrote during a floor transition");
#endif
}
} // namespace
namespace isaac::rooms {
bool stateReady() {
    return crimeReady;
}
} // namespace isaac::rooms
namespace isaac::runtime {
bool replica() {
    return ::replica;
}
void abort(const std::string& message) {
    error = message;
}
} // namespace isaac::runtime
int main() {
    try {
        configure();
        auto* image = static_cast<unsigned char*>(VirtualAlloc(
            nullptr, privateGameImageBytes, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate actor-state fixture");
        state::image = address(image);
        auto* entry = image + getHudEntry;
        entry[0] = 0xe9;
        auto relative = address(reinterpret_cast<void*>(getHud)) - address(entry + 5);
        std::memcpy(entry + 1, &relative, 4);
        FlushInstructionCache(GetCurrentProcess(), entry, 5);
        std::array<unsigned char, 32> game{};
        std::vector<unsigned char> hud(hudStride * 8, 0xa5);
        currentGame = game.data();
        currentHud = hud.data();
        field<Address>(image, gameGlobal) = address(game.data());
        Player host, guest, replacement;
        localPlayers = {address(host.data.data())};
        teamPlayers = {address(host.data.data()), address(guest.data.data())};
        for (unsigned i = 0; i < 8; ++i) {
            field<Address>(hud.data(), i * hudStride) =
                address(i == 3 || i == 7 ? guest.data.data() : host.data.data());
            field<bool>(hud.data(), i * hudStride + bagDirty) = false;
        }
        const auto hostBefore = host.data;
        auto sprites = invoke(host, state::actorSprites);
        require(sprites.arraySize == 12 && sprites.inserted == 12 && host.data == hostBefore &&
                    rosterQueries.back() == false,
                "Actor sprites lost native order or changed player resources");
        std::vector<Address> expected;
        for (auto offset : spriteOffsets)
            expected.push_back(address(host.data.data()) + offset);
        for (unsigned i = 0; i < 7; ++i)
            expected.push_back(address(host.data.data()) + chargesOffset + i * 0x114);
        expected.push_back(address(host.costumes.data()));
        expected.push_back(address(host.costumes.data()) + 0x130);
        for (unsigned i = 0; i < expected.size(); ++i)
            require((*sprites.wrappers[i])[0] == 0x12345678 &&
                        (*sprites.wrappers[i])[1] == expected[i],
                    "Borrowed Sprite wrapper changed identity or resource pointer");
        field<Address>(host.data.data(), costumesOffset + 4) += 1;
        require(invoke(host, state::actorSprites).wrappers.empty(),
                "Malformed costume array issued wrappers");
        field<Address>(host.data.data(), costumesOffset + 4) -= 1;
        field<Address>(host.data.data(), costumesOffset + 8) -= 0x130;
        require(invoke(host, state::actorSprites).wrappers.empty(),
                "Costume array exceeded native capacity");
        field<Address>(host.data.data(), costumesOffset + 8) += 0x130;
        localPlayers = {address(replacement.data.data())};
        require(invoke(host, state::actorSprites).wrappers.empty(),
                "Old roster wrapper survived Game replacement");
        require(invoke(replacement, state::actorSprites).wrappers.size() == 12,
                "New roster retained old Sprite owner");

        const std::array<std::array<unsigned, 2>, 4> pockets{{{2048, 0}, {101, 1}, {3, 2}, {4, 2}}};
        for (unsigned i = 0; i < pockets.size(); ++i) {
            field<unsigned>(host.data.data(), pocketsOffset + i * 8) = pockets[i][0];
            field<unsigned>(host.data.data(), pocketsOffset + i * 8 + 4) = pockets[i][1];
        }
        const auto pocketPacket = invoke(host, state::actorPockets).output;
        require(pocketPacket ==
                        bytes("0000080000000000000000650000000100000003000000020000000400000002") &&
                    rosterQueries.back(),
                "Ordered pockets changed bytes or ignored the full team roster");
        rejection(guest, state::actorPockets, pocketPacket);
        replica = true;
        for (unsigned n = 0; n < pocketPacket.size(); ++n)
            rejection(guest, state::actorPockets, pocketPacket.substr(0, n));
        rejection(guest, state::actorPockets, pocketPacket + 'x');
        for (const auto& [offset, value] :
             {std::pair{0u, "00010000"}, {4u, "00000003"}, {16u, "00000002"}, {24u, "00000005"}}) {
            auto invalid = pocketPacket;
            invalid.replace(offset, 4, bytes(value));
            rejection(guest, state::actorPockets, invalid);
        }
        auto expectedGuest = guest.data;
        std::memcpy(expectedGuest.data() + pocketsOffset, host.data.data() + pocketsOffset, 32);
        require(invoke(guest, state::actorPockets, &pocketPacket).success &&
                    guest.data == expectedGuest,
                "Pockets restore altered unrelated scalar or owned state");
        require(invoke(guest, state::actorPockets).output == pocketPacket,
                "Pockets capture/apply failed to round-trip");
        auto repeated = guest.data;
        require(invoke(guest, state::actorPockets, &pocketPacket).success && guest.data == repeated,
                "Repeated pocket snapshot changed state");
        teamPlayers = {address(host.data.data())};
        rejection(guest, state::actorPockets, pocketPacket);
        teamPlayers.push_back(address(guest.data.data()));

        for (unsigned i = 0; i < 8; ++i)
            field<std::uint8_t>(host.data.data(), bagOffset + i) = i + 1;
        field<unsigned>(host.data.data(), previewOffset) = 710;
        const auto bag = invoke(host, state::actorCraftingBag).output;
        require(bag == bytes("0102030405060708000002c6"), "Crafting bag changed wire bytes");
        auto hudBefore = hud;
        for (unsigned n = 0; n < bag.size(); ++n)
            rejection(guest, state::actorCraftingBag, bag.substr(0, n));
        rejection(guest, state::actorCraftingBag, bag + 'x');
        auto invalidBag = bag;
        invalidBag[7] = 30;
        rejection(guest, state::actorCraftingBag, invalidBag);
        invalidBag = bag;
        invalidBag[2] = 0;
        rejection(guest, state::actorCraftingBag, invalidBag);
        invalidBag = bag;
        invalidBag.replace(8, 4, bytes("00010000"));
        rejection(guest, state::actorCraftingBag, invalidBag);
        require(hud == hudBefore && hudCalls == 0, "Rejected bag snapshot touched native HUD");
        replica = false;
        rejection(guest, state::actorCraftingBag, bag);
        replica = true;
        expectedGuest = guest.data;
        std::memcpy(expectedGuest.data() + bagOffset, host.data.data() + bagOffset, 8);
        field<unsigned>(expectedGuest.data(), previewOffset) = 710;
        require(invoke(guest, state::actorCraftingBag, &bag).success &&
                    guest.data == expectedGuest && hudCalls == 1,
                "Bag applied to wrong version or bypassed HUD query");
        auto expectedHud = hudBefore;
        for (unsigned i : {3u, 7u})
            field<bool>(expectedHud.data(), i * hudStride + bagDirty) = true;
        require(hud == expectedHud, "Bag invalidated another actor's HUD or wrote owned resources");
        for (unsigned i : {3u, 7u})
            field<bool>(hud.data(), i * hudStride + bagDirty) = false;
        require(invoke(guest, state::actorCraftingBag, &bag).success && hudCalls == 1 &&
                    hud == hudBefore,
                "Repeated bag snapshot restarted cached animation");
        const auto emptyBag = std::string(12, '\0');
        currentHud = nullptr;
        require(invoke(guest, state::actorCraftingBag, &emptyBag).success,
                "Missing HUD rejected valid empty bag");
        currentHud = hud.data();
        const auto abi = native_fixture::call(entry, game.data(), {});
        require(abi.balanced && abi.preserved && abi.eax == address(hud.data()),
                "HUD query violated thiscall ABI");

        const auto poop = bytes("00000019010203090a0b");
        replica = false;
        rejection(guest, state::actorPoop, poop);
        replica = true;
        field<int>(guest.data.data(), typeOffset) = 0;
        rejection(guest, state::actorPoop, poop);
        field<int>(guest.data.data(), typeOffset) = 25;
        for (unsigned n = 0; n < poop.size(); ++n)
            rejection(guest, state::actorPoop, poop.substr(0, n));
        rejection(guest, state::actorPoop, poop + 'x');
        auto invalidPoop = poop;
        invalidPoop.replace(0, 4, bytes("80000000"));
        rejection(guest, state::actorPoop, invalidPoop);
        invalidPoop = poop;
        invalidPoop[9] = 12;
        rejection(guest, state::actorPoop, invalidPoop);
        expectedGuest = guest.data;
        field<unsigned>(expectedGuest.data(), poopMana) = 25;
        std::memcpy(expectedGuest.data() + poopQueue, poop.data() + 4, 6);
        require(invoke(guest, state::actorPoop, &poop).success && guest.data == expectedGuest,
                "Poop resource queue touched another field or its future RNG queue");
        require(invoke(guest, state::actorPoop, &poop).success && guest.data == expectedGuest,
                "Repeated poop state changed data");
        teamPlayers = {address(host.data.data())};
        rejection(guest, state::actorPoop, poop);
        teamPlayers.push_back(address(guest.data.data()));
        for (auto function : {state::actorPockets, state::actorCraftingBag, state::actorPoop})
            for (unsigned size : {0u, 4u, 12u, 0x11cu}) {
                lua_State L;
                L.wrapper = {0, address(guest.data.data()) + spriteOffset};
                L.userdataBytes = size;
                require(function(&L) == 1 && !L.success && L.output.empty(),
                        "Owning Sprite accepted as an entity");
            }
        for (auto function : {state::actorPockets, state::actorCraftingBag, state::actorPoop}) {
            lua_State L;
            L.wrapper = {0, spriteOffset};
            require(function(&L) == 1 && !L.success, "Null entity was dereferenced");
        }
        checkCrimeView(image);
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout << "Actor Sprite borrowing, pocket/bag/poop wire bytes, ownership and atomic "
                     "validation passed\n";
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}

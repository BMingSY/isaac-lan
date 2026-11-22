#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/room_data.cpp"
#include <cstring>
#include <iostream>
#ifdef ISAAC_LAN_TEST_REPENTANCE
constexpr unsigned gameGlobal = 0x7fd65c, descEntry = 0x30e0f0, cacheEntry = 0x4e2e40;
constexpr unsigned roomOffset = 0x18190, indexOffset = 0x18194, dimensionOffset = 0x1819c;
constexpr unsigned mapOffset = 0x1796c, countOffset = 0x1815c, frameOffset = 0x1a30dc;
constexpr unsigned waterOffset = 0x7344, savedStride = 0x68, mapState = 0x101904,
                   mapTimer = 0x10190c;
constexpr std::array<unsigned, 2> caches{0x1a2ac8, 0x1a2c28};
constexpr int minimumRoom = -18;
#else
constexpr unsigned gameGlobal = 0x8994f8, descEntry = 0x348580, cacheEntry = 0x5a2650;
constexpr unsigned roomOffset = 0x18300, indexOffset = 0x18304, dimensionOffset = 0x1830c;
constexpr unsigned mapOffset = 0x17adc, countOffset = 0x182cc, frameOffset = 0x26508;
constexpr unsigned waterOffset = 0x7478, savedStride = 0x78, mapState = 0x22ed4, mapTimer = 0x22edc;
constexpr std::array<unsigned, 2> caches{0x25ef4, 0x26054};
constexpr int minimumRoom = -20;
#endif
struct lua_State {
    int top = 0;
    std::array<long long, 2> integers{};
    std::array<double, 2> numbers{};
    std::string input, output;
    std::vector<bool> flags;
    std::vector<long long> table;
    long long pushed = 0;
};
namespace {
namespace state = isaac::engine::native_room_data;
using Address = std::uintptr_t;
struct Vector {
    Address begin, end, capacity;
    auto operator<=>(const Vector&) const = default;
};
bool replica = false, enabled = true, idle = true, scoped = true, shell = false;
unsigned descCalls = 0;
std::vector<Address> cacheCalls;
std::string error;
unsigned char* image;
Address address(const void* pointer) {
    return reinterpret_cast<Address>(pointer);
}
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
struct Game {
    std::vector<unsigned char> data = std::vector<unsigned char>(0x290000, 0xa5);
    std::array<unsigned char, 0x7900> room{};
    std::array<unsigned char, 0xb8> sentinel{}, special{};
    std::array<unsigned char, 0x5c> config{};
    std::vector<unsigned char> entities = std::vector<unsigned char>(savedStride * 4, 0xa5);
    unsigned char* descriptor(unsigned index) {
        return data.data() + 0x14 + index * 0xb8;
    }
    Game() {
        for (unsigned i = 0; i < 507; ++i)
            field<int>(data.data(), mapOffset + i * 4) = -1;
        field<unsigned>(data.data(), countOffset) = 0;
        field<Address>(data.data(), roomOffset) = address(room.data());
        field<int>(data.data(), indexOffset) = 42;
        field<int>(data.data(), dimensionOffset) = 2;
        field<Address>(room.data(), 4) = address(descriptor(7));
        for (unsigned i : {42u, 43u})
            field<int>(data.data(), mapOffset + (2 * 169 + i) * 4) = 7;
        for (unsigned i : {42u, 43u})
            field<int>(data.data(), mapOffset + i * 4) = 7;
        field<int>(data.data(), mapOffset + 100 * 4) = 9;
        const std::array<unsigned, 10> offsets{0, 4, 8, 12, 16, 0x2c, 0x38, 0x3c, 0x48, 0x4c};
        const std::array<unsigned, 10> values{1, 0, 1, 123, 0, 5, 0x55, 1, 8, 2};
        for (unsigned i = 0; i < offsets.size(); ++i)
            field<unsigned>(config.data(), offsets[i]) = values[i];
        config[0x46] = 26;
        config[0x47] = 14;
        field<unsigned>(config.data(), 0x28) = 15;
        auto* desc = descriptor(7);
        field<int>(desc, 0) = 40;
        field<int>(desc, 4) = 42;
        field<int>(desc, 8) = 7;
        field<int>(desc, 12) = 2;
        field<Address>(desc, 0x10) = address(config.data());
        field<Address>(desc, 0x14) = 0;
        field<unsigned>(desc, 0x18) = 5;
        for (unsigned i = 0; i < 8; ++i)
            field<int>(desc, 0x1c + i * 4) = i == 0 ? 43 : i == 2 ? 100 : -1;
        for (unsigned i = 0; i < 4; ++i)
            field<unsigned>(desc, 0x58 + i * 4) = 111 * (i + 1);
        field<Address>(descriptor(9), 0x10) = address(config.data());
        field<int>(descriptor(9), 4) = 99;
        field<Vector>(desc, 0x74) = {address(entities.data()),
                                     address(entities.data() + entities.size()),
                                     address(entities.data() + entities.size())};
    }
};
Game* current = nullptr;
void* __attribute__((fastcall)) descriptor(void* game, void*, int index, int dimension) {
    require(current && game == current->data.data(), "Descriptor queried a stale Game");
    require(index >= minimumRoom && index < 169 && dimension >= 0 && dimension < 3,
            "Invalid room reached native lookup");
    ++descCalls;
    if (index < 0)
        return current->special.data();
    const auto list = field<int>(current->data.data(), mapOffset + (dimension * 169 + index) * 4);
    return list >= 0 && list < 507 ? current->descriptor(list) : current->sentinel.data();
}
void __attribute__((fastcall)) cache(void* value, void*) {
    cacheCalls.push_back(address(value));
}
void select(Game& game) {
    current = &game;
    field<Address>(image, gameGlobal) = address(game.data.data());
}
void configure() {
    state::lua.getTop = [](lua_State* L) { return L->top; };
    state::lua.checkInteger = [](lua_State* L, int index) { return L->integers[index - 1]; };
    state::lua.checkNumber = [](lua_State* L, int index) { return L->numbers[index - 1]; };
    state::lua.checkString = [](lua_State* L, int, std::size_t* size) {
        *size = L->input.size();
        return L->input.c_str();
    };
    state::lua.pushLString = [](lua_State* L, const char* value, std::size_t size) -> const char* {
        L->output.assign(value, size);
        return L->output.c_str();
    };
    state::lua.pushBoolean = [](lua_State* L, int value) { L->flags.push_back(value); };
    state::lua.createTable = [](lua_State* L, int size, int hash) {
        require(size == 8 && hash == 0, "Door table shape changed");
        L->table.resize(size);
    };
    state::lua.pushInteger = [](lua_State* L, long long value) { L->pushed = value; };
    state::lua.rawSetI = [](lua_State* L, int table, long long index) {
        require(table == -2 && index >= 1 && index <= 8, "Door table index changed");
        L->table[index - 1] = L->pushed;
    };
    state::context = {
        [] { return enabled; }, [] { return idle; },
        [] { return enabled && scoped && !shell && current ? address(current->room.data()) : 0; }};
}
void jump(unsigned rva, void* target) {
    auto* entry = image + rva;
    entry[0] = 0xe9;
    const auto relative = address(target) - address(entry + 5);
    std::memcpy(entry + 1, &relative, 4);
    FlushInstructionCache(GetCurrentProcess(), entry, 5);
}
void u32(std::string& output, unsigned value) {
    for (int shift = 24; shift >= 0; shift -= 8)
        output += static_cast<char>(value >> shift);
}
void replaceWord(std::string& output, unsigned offset, unsigned value) {
    std::string bytes;
    u32(bytes, value);
    output.replace(offset, 4, bytes);
}
std::string layoutPacket(int index = 42, int list = 7) {
    std::string output;
    for (unsigned value :
         {2u, static_cast<unsigned>(index), static_cast<unsigned>(index < 0 ? index : 40),
          static_cast<unsigned>(list)})
        u32(output, value);
    output += index < 0 ? '\0' : '\2';
    if (index >= 0) {
        output += char(42);
        output += char(43);
    }
    for (unsigned value : {1u, 0u, 1u, 123u, 0u, 5u, 0x55u, 1u, 8u, 2u})
        u32(output, value);
    output += char(26);
    output += char(14);
    u32(output, 5);
    for (int value : {43, -1, 100, -1, -1, -1, -1, -1})
        u32(output, value);
    for (unsigned value : {111u, 222u, 333u, 444u})
        u32(output, value);
    return output;
}
using Record = std::array<unsigned, 6>;
const std::array<Record, 4> records{{{5, 20, 7, 1, 0x3f800000, 0x40000000},
                                     {100, 999, 22, 0, 0, 0},
                                     {6, 3, 0, 0, 0, 0},
                                     {5, 30, 12, 0, 0x42c80000, 0x43480000}}};
std::string mapPacket(int index = 42, unsigned count = 3) {
    std::string output;
    u32(output, 2);
    u32(output, index);
    unsigned n = 0;
    for (const auto& record : records) {
        if (record[0] == 100 || n++ >= count)
            continue;
        for (auto value : record)
            u32(output, value);
    }
    return output;
}
lua_State receive(int (*function)(lua_State*), const std::string& bytes) {
    lua_State L;
    L.top = 1;
    L.input = bytes;
    error.clear();
    function(&L);
    return L;
}
lua_State query(int (*function)(lua_State*), long long index, long long dimension) {
    lua_State L;
    L.top = 2;
    L.integers = {index, dimension};
    error.clear();
    function(&L);
    return L;
}
bool success(const lua_State& L) {
    return !L.flags.empty() && L.flags[0];
}
void rejectLayout(const std::string& bytes) {
    const auto before = current->data;
    const auto sentinel = current->sentinel, special = current->special;
    const auto config = state::replicaLayouts;
    require(!success(receive(state::roomLayout, bytes)) && current->data == before &&
                current->sentinel == sentinel && current->special == special &&
                state::replicaLayouts == config,
            "Invalid layout partially wrote descriptors, cells or borrowed configuration");
}
} // namespace
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
        image = static_cast<unsigned char*>(VirtualAlloc(
            nullptr, privateGameImageBytes, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image, "Allocate room data fixture");
        state::image = address(image);
        jump(descEntry, reinterpret_cast<void*>(descriptor));
        jump(cacheEntry, reinterpret_cast<void*>(cache));
        Game host, guest;
        select(host);
        const auto packet = layoutPacket();
        const auto hostBefore = host.data;
        lua_State now;
        require(state::roomLayout(&now) == 1 && now.output == packet && host.data == hostBefore,
                "Current room layout changed bytes or touched host state");
        require(query(state::roomLayout, 43, 2).output == packet,
                "Large room cell did not use its canonical descriptor index");
        const auto abi = native_fixture::call(image + descEntry, host.data.data(), {42, 2});
        require(abi.balanced && abi.preserved && abi.eax == address(host.descriptor(7)),
                "Descriptor ABI changed");
        for (auto fn : {state::roomLayout, state::mapPickups}) {
            const auto calls = descCalls;
            for (auto key : {std::pair{169ll, 0ll},
                             {-21ll, 0ll},
                             {0ll, 3ll},
                             {0x10000002all, 2ll},
                             {42ll, 0x100000002ll}})
                require(!success(query(fn, key.first, key.second)) && descCalls == calls,
                        "Out-of-range Lua room query reached native lookup");
        }
        rejectLayout(packet);
        replica = true;
        select(guest);
        for (unsigned i = 0; i < 507; ++i)
            field<int>(guest.data.data(), mapOffset + i * 4) = -1;
        field<Address>(guest.descriptor(7), 0x10) = 0;
        const auto guestBefore = guest.data;
        const auto sentinelBefore = guest.sentinel;
        const auto callsBefore = descCalls;
        require(success(receive(state::roomLayout, packet)) && guest.sentinel == sentinelBefore &&
                    descCalls == callsBefore,
                "New red room used native sentinel instead of constructed descriptor array");
        auto expectedGame = guestBefore;
        auto* expectedDesc = expectedGame.data() + 0x14 + 7 * 0xb8;
        const auto configPointer = field<Address>(guest.descriptor(7), 0x10);
        field<Address>(expectedDesc, 0x10) = configPointer;
        field<Address>(expectedDesc, 0x14) = 0;
        for (unsigned i : {42u, 43u})
            field<int>(expectedGame.data(), mapOffset + (2 * 169 + i) * 4) = 7;
        field<unsigned>(expectedGame.data(), countOffset) = 8;
        require(guest.data == expectedGame && std::memcmp(reinterpret_cast<void*>(configPointer),
                                                          host.config.data(), 0x5c) == 0,
                "Replica layout wrote unrelated fields, spawns or native string ownership");
        require(query(state::roomLayout, 42, 2).output == packet, "Layout failed to round-trip");
        require(success(receive(state::roomLayout, packet)) && guest.data == expectedGame &&
                    field<Address>(guest.descriptor(7), 0x10) == configPointer,
                "Repeated room snapshot moved the borrowed config address");
        for (unsigned n = 0; n < packet.size(); ++n)
            rejectLayout(packet.substr(0, n));
        rejectLayout(packet + 'x');
        for (auto [offset, value] :
             {std::pair{0u, 3u}, {4u, 169u}, {8u, 169u}, {12u, 507u}, {27u, 0u}, {51u, 13u}}) {
            auto invalid = packet;
            replaceWord(invalid, offset, value);
            rejectLayout(invalid);
        }
        for (auto [offset, value] : {std::pair{17u, 44u}, {18u, 169u}, {59u, 27u}, {60u, 15u}}) {
            auto invalid = packet;
            invalid[offset] = char(value);
            rejectLayout(invalid);
        }
        require(success(receive(state::roomLayout, layoutPacket(-12, -12))) &&
                    field<int>(guest.special.data(), 4) == -12,
                "Lazily initialized special room lost native descriptor");
#ifdef ISAAC_LAN_TEST_REPENTANCE
        const auto beforeCalls = descCalls;
        rejectLayout(layoutPacket(-19, -19));
        require(descCalls == beforeCalls, "Unsupported vanilla special room wrote sentinel");
#else
        require(success(receive(state::roomLayout, layoutPacket(-20, -20))),
                "Repentance+ special room range changed");
#endif
        select(host);
        replica = false;
        constexpr std::array<unsigned, 6> savedFields{0, 4, 8, 0x14, 0x28, 0x2c};
        for (unsigned i = 0; i < records.size(); ++i)
            for (unsigned j = 0; j < 6; ++j)
                field<unsigned>(host.entities.data() + i * savedStride, savedFields[j]) =
                    records[i][j];
        const auto map = mapPacket();
        require(query(state::mapPickups, 42, 2).output == map,
                "Map entity stride/filter or fixed wire fields changed");
        require(!success(receive(state::mapPickups, map)),
                "Authority accepted replica map metadata");
        auto& native = field<Vector>(host.descriptor(7), 0x74);
        const auto savedNative = native;
        native.end += 1;
        require(query(state::mapPickups, 42, 2).output.empty(),
                "Malformed native map vector was traversed");
        native = savedNative;
        replica = true;
        auto accepted = receive(state::mapPickups, map);
        require(accepted.flags == std::vector<bool>({true, true}) && native == savedNative,
                "Map receive altered game-owned saves");
        require(receive(state::mapPickups, map).flags == std::vector<bool>({true, false}),
                "Repeated map receive reported a change");
        for (unsigned n = 0; n < map.size(); ++n) {
            if (n >= 8 && (n - 8) % 24 == 0)
                continue;
            require(!success(receive(state::mapPickups, map.substr(0, n))) &&
                        query(state::mapPickups, 42, 2).output == map,
                    "Malformed map payload replaced prior state");
        }
        auto invalidMap = map;
        replaceWord(invalidMap, 8, 100);
        require(!success(receive(state::mapPickups, invalidMap)), "Non-map entity accepted");
        state::withMapPickups([&] {
            require(native.end - native.begin == 3 * savedStride &&
                        native.begin != savedNative.begin,
                    "Map cache did not borrow version-sized records");
            const auto outer = native;
            std::vector<unsigned char> expected(3 * savedStride);
            unsigned at = 0;
            for (const auto& record : records)
                if (record[0] != 100) {
                    for (unsigned i = 0; i < 6; ++i)
                        field<unsigned>(expected.data() + at, savedFields[i]) = record[i];
                    at += savedStride;
                }
            require(std::memcmp(reinterpret_cast<void*>(native.begin), expected.data(),
                                expected.size()) == 0,
                    "Borrowed map records carried pointers or unrelated native state");
            require(success(receive(state::mapPickups, mapPacket(42, 1))),
                    "Nested map update failed");
            state::withMapPickups([&] {
                require(native.end - native.begin == savedStride, "Nested cache retained old map");
            });
            require(native == outer && std::memcmp(reinterpret_cast<void*>(outer.begin),
                                                   expected.data(), expected.size()) == 0,
                    "Nested update freed or replaced the outer borrowed storage");
            state::resetMap();
            require(std::memcmp(reinterpret_cast<void*>(outer.begin), expected.data(),
                                expected.size()) == 0,
                    "Floor reset freed an active cache borrow");
        });
        require(native == savedNative, "Map cache did not restore native owners");
        require(success(receive(state::mapPickups, map)) &&
                    success(receive(state::mapPickups, mapPacket(43, 1))),
                "Aliased map setup failed");
        bool caught = false;
        try {
            state::withMapPickups([&] { throw std::runtime_error("cache failure"); });
        } catch (const std::runtime_error&) {
            caught = true;
        }
        require(caught && native == savedNative,
                "Aliased/exception map scopes restored in wrong order");
        state::resetMap();
        require(query(state::mapPickups, 42, 2).output == map,
                "Map reset retained an old received view");
        replica = false;
        lua_State connections;
        connections.integers[0] = 42;
        const auto beforeConnections = host.data;
        require(state::roomConnections(&connections) == 1 &&
                    connections.table == std::vector<long long>({42, -1, 99, -1, -1, -1, -1, -1}) &&
                    host.data == beforeConnections,
                "Door connections changed native geometry or failed canonical lookup");
        idle = false;
        lua_State busy;
        busy.integers[0] = 42;
        state::roomConnections(&busy);
        require(!success(busy), "Busy room connections were accepted");
        idle = true;
        const auto beforeWater = host.room;
        lua_State flow;
        flow.numbers = {0.6, 0.8};
        state::roomWaterCurrent(&flow);
        require(!success(flow) && host.room == beforeWater, "Authority water was overwritten");
        replica = true;
        for (unsigned unavailable = 0; unavailable < 3; ++unavailable) {
            enabled = unavailable != 0;
            scoped = unavailable != 1;
            shell = unavailable == 2;
            lua_State denied;
            denied.numbers = {0.6, 0.8};
            state::roomWaterCurrent(&denied);
            require(!success(denied) && host.room == beforeWater,
                    "Uninitialized room shell received geometry");
        }
        enabled = scoped = true;
        shell = false;
        for (auto values : {std::array{1.0, 1.0}, std::array<double, 2>{INFINITY, 0.0},
                            std::array<double, 2>{NAN, 0.0}}) {
            lua_State denied;
            denied.numbers = values;
            state::roomWaterCurrent(&denied);
            require(!success(denied) && host.room == beforeWater,
                    "Invalid water vector wrote state");
        }
        lua_State validFlow;
        validFlow.numbers = {0.6, 0.8};
        state::roomWaterCurrent(&validFlow);
        auto expectedRoom = beforeWater;
        field<float>(expectedRoom.data(), waterOffset) = 0.6f;
        field<float>(expectedRoom.data(), waterOffset + 4) = 0.8f;
        require(success(validFlow) && host.room == expectedRoom, "Water wrote wrong room layout");
        auto beforeClock = host.data;
        lua_State clock;
        clock.integers[0] = 0xffffffff;
        state::stateClock(&clock);
        field<unsigned>(beforeClock.data(), frameOffset) = 0xffffffff;
        require(host.data == beforeClock, "Replica clock changed unrelated Game state");
        clock.integers[0] = -1;
        state::stateClock(&clock);
        require(host.data == beforeClock, "Invalid clock wrapped into state");
        field<int>(host.data.data(), mapState) = 0;
        lua_State refresh;
        state::refreshMap(&refresh);
        require(success(refresh) &&
                    cacheCalls == std::vector<Address>({address(host.data.data()) + caches[0],
                                                        address(host.data.data()) + caches[1]}) &&
                    field<int>(host.data.data(), mapState) == 1 &&
                    field<int>(host.data.data(), mapTimer) == 2,
                "Map refresh used wrong native cache/state offsets");
        field<int>(host.data.data(), mapState) = 2;
        field<int>(host.data.data(), mapTimer) = 77;
        state::refreshMap(&refresh);
        require(field<int>(host.data.data(), mapTimer) == 77,
                "Map refresh restarted active native state");
        enabled = false;
        const auto cached = cacheCalls.size();
        lua_State disabled;
        state::refreshMap(&disabled);
        require(!success(disabled) && cacheCalls.size() == cached,
                "Disabled map invoked native renderer");
        enabled = true;
        select(guest);
        cacheCalls.clear();
        state::refreshMap(&refresh);
        require(cacheCalls[0] == address(guest.data.data()) + caches[0],
                "Map refresh retained previous Game owner");
        const auto guestStable = guest.data;
        field<Address>(image, gameGlobal) = 0;
        require(!success(receive(state::roomLayout, packet)) &&
                    !success(receive(state::mapPickups, map)),
                "Destroyed Game accepted snapshots");
        state::stateClock(&clock);
        lua_State gone;
        state::refreshMap(&gone);
        require(!success(gone) && guest.data == guestStable,
                "Destroyed Game received state writes");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout
            << "Room layouts, descriptor bounds, map ownership scopes, water and clocks passed\n";
        return 0;
    } catch (const std::exception& failure) {
        std::cerr << failure.what() << '\n';
        return 1;
    }
}

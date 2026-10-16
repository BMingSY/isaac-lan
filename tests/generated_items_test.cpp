// Exercise the production x86 registry adapter without launching the game.
#include "test_support.h"
#include "engine/versions/j460/generated_items.cpp"
#include <array>
#include <cstdio>

namespace {
namespace adapter = isaac::generated_items;
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
bool replica = false, result = false;
std::string input, output, error;
unsigned arguments = 0, generated = 0;
std::array<std::array<unsigned, 2>, 1024> configs{};
std::array<std::array<unsigned, 3>, 1024> entries{};
std::array<Address, 1024> pointers{};
std::array<Address, 3> registry{};
void reset() {
    registry = {reinterpret_cast<Address>(pointers.data()),
                reinterpret_cast<Address>(pointers.data()),
                reinterpret_cast<Address>(pointers.data() + pointers.size())};
    generated = 0;
    error.clear();
    result = false;
}
int __attribute__((thiscall)) generateFixture(void* self, unsigned seed, unsigned flags) {
    require(self == registry.data() && !flags,
            "Generator ABI/flags differ from native restoration");
    const unsigned i = (registry[1] - registry[0]) / 4;
    configs[i] = {0, ~i};
    entries[i] = {reinterpret_cast<Address>(configs[i].data()), i, seed};
    pointers[i] = reinterpret_cast<Address>(entries[i].data());
    registry[1] += 4;
    ++generated;
    return static_cast<int>(~i);
}
std::string packed(std::initializer_list<unsigned> seeds) {
    isaac::lan::Writer w(isaac::lan::Message::world);
    for (unsigned seed : seeds)
        w.u32(seed);
    return {reinterpret_cast<const char*>(w.bytes.data() + 1), w.bytes.size() - 1};
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
        Address game = reinterpret_cast<Address>(registry.data()) - 0x67758;
        adapter::image = reinterpret_cast<Address>(&game) - isaac::engine::j460::globals::game;
        adapter::originalGenerate = generateFixture;
        adapter::lua.getTop = [](lua_State*) { return static_cast<int>(arguments); };
        adapter::lua.checkString = [](lua_State*, int, std::size_t* size) {
            *size = input.size();
            return input.c_str();
        };
        adapter::lua.pushString = [](lua_State*, const char* bytes, std::size_t size) {
            output.assign(bytes, size);
            return output.c_str();
        };
        adapter::lua.pushBoolean = [](lua_State*, int value) { result = value; };
        reset();
        arguments = 1;
        input = packed({123, 456});
        adapter::state(nullptr);
        require(!error.empty() && generated == 0, "Authority accepted replica mutation");
        replica = true;
        error.clear();
        adapter::state(nullptr);
        require(result && error.empty() && generated == 2,
                "Definitions were not appended in order");
        adapter::state(nullptr);
        require(generated == 2, "Repeated snapshot regenerated definitions");
        arguments = 0;
        adapter::state(nullptr);
        require(output == input, "Normalized seed capture differs");
        arguments = 1;
        for (const auto& invalid : {packed({123}), packed({124, 456}), packed({123, 456, 789, 0}),
                                    std::string(1, 'x'), std::string(4100, 'x')}) {
            input = invalid;
            error.clear();
            result = true;
            adapter::state(nullptr);
            require(!result && !error.empty() && generated == 2,
                    "Invalid snapshot partially mutated the registry");
        }
        error.clear();
        input = packed({123, 456, 789});
        adapter::state(nullptr);
        require(result && generated == 3 && error.empty(), "Valid suffix was not appended");
        require(adapter::generate(registry.data(), nullptr, 100, 0) == 25 &&
                    adapter::generate(registry.data(), nullptr, 100, 8) == 105 && generated == 3,
                "Replica room construction appended local definitions");
        replica = false;
        require(adapter::generate(registry.data(), nullptr, 100, 0) == -4 && generated == 4,
                "Authority generation was intercepted");
        for (const auto field : {0u, 1u}) {
            auto old = configs[0][field];
            if (field == 1)
                configs[0][field] = 0;
            else
                entries[0][2] = 0;
            arguments = 0;
            error.clear();
            adapter::state(nullptr);
            require(!error.empty(), "Corrupt native registry was accepted");
            configs[0][field] = old;
            entries[0][2] = 123;
        }
        reset();
        for (unsigned i = 0; i < 1024; ++i)
            generateFixture(registry.data(), i + 1, 0);
        arguments = 0;
        adapter::state(nullptr);
        require(error.empty() && output.size() == 4096 && configs.back()[1] == unsigned(-1024),
                "Native registry capacity was not captured");
        const auto end = registry[1];
        for (const auto invalidEnd : {registry[0] - 4, registry[0] + 1, end + 4}) {
            registry[1] = invalidEnd;
            error.clear();
            adapter::state(nullptr);
            require(!error.empty(), "Malformed native vector bounds were accepted");
        }
        registry[1] = end;
        std::vector<unsigned> actor(0x2000 / 4), nativeGame(0x68000 / 4);
        std::array<unsigned, 6> head{}, root{}, left{}, right{};
        const auto address = [](const auto& value) {
            return reinterpret_cast<Address>(value.data());
        };
        head[1] = address(root);
        head[3] = 0x100;
        root = {address(left), address(head), address(right), 0, unsigned(-4), 3};
        left = {address(head), address(root), address(head), 0, unsigned(-8), 0};
        right = {address(head), address(root), address(head), 0, unsigned(-1), 1};
        actor[0x1fcc / 4] = address(head);
        actor[0x1fd0 / 4] = 3;
        const auto beforeActor = actor;
        require(adapter::ownedCount(address(actor), -4) == 3 &&
                    adapter::ownedCount(address(actor), -8) == 0 &&
                    adapter::ownedCount(address(actor), -1) == 1 &&
                    adapter::ownedCount(address(actor), -2) == 0 && actor == beforeActor,
                "Generated inventory count lost duplicates, zero or missing entries");
        auto reject = [&] {
            bool rejected = false;
            try {
                adapter::ownedCount(address(actor), -8);
            } catch (const std::runtime_error&) {
                rejected = true;
            }
            require(rejected, "Malformed generated inventory was accepted");
        };
        root[0] = address(root);
        reject();
        root[0] = address(left);
        left[5] = unsigned(-1);
        reject();
        left[5] = 0;
        actor[0x1fd0 / 4] = 1025;
        reject();
        actor[0x1fd0 / 4] = 3;
        std::array<Address, 1> roster{address(actor)};
        nativeGame[0x1baa8 / 4] = address(roster);
        nativeGame[0x1baac / 4] = address(roster) + 4;
        game = address(nativeGame);
        actor[0x28 / 4] = 1;
        std::array<Address, 2> wrapper{0, address(actor) + 0x48};
        static void* spriteWrapper;
        static long long observedCount;
        spriteWrapper = wrapper.data();
        adapter::lua.toUserdata = [](lua_State*, int) { return spriteWrapper; };
        adapter::lua.rawLength = [](lua_State*, int) -> std::size_t { return 8; };
        adapter::lua.checkInteger = [](lua_State*, int) -> long long { return -4; };
        adapter::lua.pushInteger = [](lua_State*, long long count) { observedCount = count; };
        error.clear();
        adapter::count(nullptr);
        require(error.empty() && observedCount == 3, "Current player sprite count failed");
        wrapper[1] += 4;
        adapter::count(nullptr);
        require(!error.empty(), "Non-player sprite accepted for generated inventory");
        std::puts("PASS x86 generated item registry, ordering, duplicate and malformed snapshots");
        return 0;
    } catch (const std::exception& exception) {
        std::fprintf(stderr, "%s\n", exception.what());
        return 1;
    }
}

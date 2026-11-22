// Exercise the production x86 registry adapter without launching the game.
#include "test_support.h"
#include "engine/versions/common/generated_items.cpp"
#ifdef ISAAC_LAN_TEST_J835
#include "engine/versions/j835/entrypoints.h"
#else
#include "engine/versions/j511/entrypoints.h"
#endif
#include <array>
#include <cstdio>

namespace {
namespace adapter = isaac::generated_items;
#ifdef ISAAC_LAN_TEST_J835
namespace backend = isaac::engine::j835;
constexpr unsigned registryOffset = 0x283c20, inventoryHead = 0x1ec4, inventorySize = 0x1ec8;
constexpr unsigned playersOffset = 0x1ba50, spriteOffset = 0x3c;
#else
namespace backend = isaac::engine::j511;
constexpr unsigned registryOffset = 0x67e48, inventoryHead = 0x1fcc, inventorySize = 0x1fd0;
constexpr unsigned playersOffset = 0x1baa8, spriteOffset = 0x48;
#endif
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
bool replica = false, result = false;
std::string input, output, error;
unsigned arguments = 0, generated = 0;
std::array<std::array<unsigned, 2>, 1024> configs{};
std::array<std::array<unsigned, 3>, 1024> entries{};
std::array<Address, 1024> pointers{};
constexpr unsigned imageSize = privateGameImageBytes;
unsigned char* image;
std::vector<unsigned> nativeGame((registryOffset + 16) / 4);
auto& registry = *reinterpret_cast<std::array<Address, 3>*>(
    reinterpret_cast<unsigned char*>(nativeGame.data()) + registryOffset);
using Generate = int(__attribute__((thiscall)) *)(void*, unsigned, unsigned);
Generate nativeGenerate, nativeRestore;
bool failGeneration = false;
struct EffectCall {
    int id;
    void* player;
    unsigned event;
    void* entity;
    const void* position;
    const void* velocity;
    bool operator==(const EffectCall&) const = default;
};
std::vector<EffectCall> effectCalls;
void __attribute__((stdcall)) triggerFixture(int id, void* player, unsigned event, void* entity,
                                             const void* position, const void* velocity) {
    effectCalls.push_back({id, player, event, entity, position, velocity});
}
void checkEffectAuthority() {
    const auto trigger =
        reinterpret_cast<adapter::TriggerEffects>(image + backend::entry::generatedItemTrigger);
    int player = 0, entity = 0;
    std::array<float, 2> position{11, 23}, velocity{-2, 7};
    // Both active use (event 0) and passive event chains share this native ABI.
    // Repeated snapshots/local updates must not execute either on the replica.
    for (bool isReplica : {false, true, false}) {
        replica = isReplica;
        for (unsigned event = 0; event != 9; ++event) {
            const auto before = effectCalls.size();
            trigger(-4, &player, event, &entity, position.data(), velocity.data());
            require(effectCalls.size() == before + (isReplica ? 0 : 1),
                    "Generated effects executed outside their authority");
            if (!isReplica)
                require(effectCalls.back() == EffectCall{-4, &player, event, &entity,
                                                         position.data(), velocity.data()},
                        "Generated effect ABI lost its borrowed arguments");
        }
    }
}
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
    if (failGeneration)
        return 25;
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
        require(!adapter::install(0), "Missing image installed generator");
        image = static_cast<unsigned char*>(
            VirtualAlloc(nullptr, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Create isolated generated item fixture");
        auto* target = image + backend::entry::generatedItemCreate;
        target[0] = 0xe9;
        const auto relative =
            reinterpret_cast<Address>(generateFixture) - reinterpret_cast<Address>(target + 5);
        std::memcpy(target + 1, &relative, 4);
        std::memset(target + 5, 0x90, 11);
        auto* effects = image + backend::entry::generatedItemTrigger;
        effects[0] = 0xe9;
        const auto effectsOffset =
            reinterpret_cast<Address>(triggerFixture) - reinterpret_cast<Address>(effects + 5);
        std::memcpy(effects + 1, &effectsOffset, 4);
        std::memset(effects + 5, 0x90, 11);
        // Copy both original arguments before CALL. Its return address is the
        // audited native save-restoration site, then consume the caller's args.
        auto* restore = image + backend::entry::generatedItemRestoreCall;
        const std::array<unsigned char, 8> copiedArguments{0xff, 0x74, 0x24, 0x08,
                                                           0xff, 0x74, 0x24, 0x08};
        std::memcpy(restore - copiedArguments.size(), copiedArguments.data(),
                    copiedArguments.size());
        restore[0] = 0xe8;
        const auto displacement = target - (restore + 5);
        std::memcpy(restore + 1, &displacement, 4);
        const std::array<unsigned char, 3> epilogue{0xc2, 0x08, 0};
        std::memcpy(restore + 5, epilogue.data(), epilogue.size());
        FlushInstructionCache(GetCurrentProcess(), image, imageSize);
        nativeGenerate = reinterpret_cast<Generate>(target);
        nativeRestore = reinterpret_cast<Generate>(restore - copiedArguments.size());
        auto& game = *reinterpret_cast<Address*>(image + backend::globals::game);
        game = reinterpret_cast<Address>(nativeGame.data());
        require(MH_CreateHook(target, reinterpret_cast<void*>(generateFixture), nullptr) == MH_OK,
                "Create foreign generator hook");
        require(!adapter::install(reinterpret_cast<Address>(image)),
                "Foreign generator conflict was ignored");
        require(MH_CreateHook(target, reinterpret_cast<void*>(generateFixture), nullptr) ==
                    MH_ERROR_ALREADY_CREATED,
                "Generator rollback removed foreign hook");
        require(MH_RemoveHook(target) == MH_OK &&
                    adapter::install(reinterpret_cast<Address>(image)),
                "Generator install did not recover");
        require(!adapter::install(reinterpret_cast<Address>(image)),
                "Duplicate generator install succeeded");
        checkEffectAuthority();
        adapter::lua.getTop = [](lua_State*) { return static_cast<int>(arguments); };
        adapter::lua.checkString = [](lua_State*, int, std::size_t* size) {
            *size = input.size();
            return input.c_str();
        };
        adapter::lua.pushLString = [](lua_State*, const char* bytes, std::size_t size) {
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
        require(nativeGenerate(registry.data(), 100, 0) == 25 &&
                    nativeGenerate(registry.data(), 100, 8) == 105 && generated == 3,
                "Replica room construction appended local definitions");
        replica = false;
        require(nativeGenerate(registry.data(), 100, 0) == -4 && generated == 4,
                "Authority generation was intercepted");
        replica = true;
        require(nativeRestore(registry.data(), 101, 0) == -5 && generated == 5,
                "Native save-restoration call was blocked on replica");
        input = packed({123, 456, 789, 100, 101, 102});
        arguments = 1;
        failGeneration = true;
        adapter::state(nullptr);
        require(!result && generated == 5,
                "Failed generation was accepted or erased existing definitions");
        failGeneration = false;
        error.clear();
        adapter::state(nullptr);
        require(result && generated == 6 && error.empty(), "Valid generation did not recover");
        replica = false;
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
        const auto validRegistry = registry;
        for (const auto invalid :
             {std::array<Address, 3>{0, 4, 4}, std::array<Address, 3>{1, 1, 1}}) {
            registry = invalid;
            error.clear();
            adapter::state(nullptr);
            require(!error.empty(), "Null or unaligned registry was accepted");
        }
        registry = validRegistry;
        std::vector<unsigned> actor(0x2100 / 4);
        std::array<unsigned, 6> head{}, root{}, left{}, right{};
        const auto address = [](const auto& value) {
            return reinterpret_cast<Address>(value.data());
        };
        head[1] = address(root);
        head[3] = 0x100;
        root = {address(left), address(head), address(right), 0, unsigned(-4), 3};
        left = {address(head), address(root), address(head), 0, unsigned(-8), 0};
        right = {address(head), address(root), address(head), 0, unsigned(-1), 1};
        actor[inventoryHead / 4] = address(head);
        actor[inventorySize / 4] = 3;
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
        root[0] = address(left) + 1;
        reject();
        root[0] = address(left);
        left[5] = unsigned(-1);
        reject();
        left[5] = 0;
        actor[inventorySize / 4] = 1025;
        reject();
        actor[inventorySize / 4] = 3;
        std::array<Address, 1> roster{address(actor)};
        nativeGame[playersOffset / 4] = address(roster);
        nativeGame[(playersOffset + 4) / 4] = address(roster) + 4;
        game = address(nativeGame);
        actor[0x28 / 4] = 1;
        std::array<Address, 2> wrapper{0, address(actor) + spriteOffset};
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
        wrapper[1] -= 4;
        nativeGame[playersOffset / 4] = 0;
        nativeGame[(playersOffset + 4) / 4] = 4;
        error.clear();
        adapter::count(nullptr);
        require(!error.empty(), "Null nonempty roster reached native memory");
        game = 0;
        error.clear();
        adapter::count(nullptr);
        require(!error.empty(), "Missing Game retained a borrowed player");
        game = address(nativeGame);
        reset();
        arguments = 0;
        adapter::state(nullptr);
        require(output.empty() && error.empty(), "New native run reused prior definitions");
        replica = true;
        arguments = 1;
        input = packed({456});
        adapter::state(nullptr);
        require(result && generated == 1 && error.empty(), "New run failed to restore new prefix");
        require(MH_Uninitialize() == MH_OK, "Remove generated item hooks");
        VirtualFree(image, 0, MEM_RELEASE);
        std::puts("PASS x86 generated item registry, ordering, duplicate and malformed snapshots");
        return 0;
    } catch (const std::exception& exception) {
        std::fprintf(stderr, "%s\n", exception.what());
        return 1;
    }
}

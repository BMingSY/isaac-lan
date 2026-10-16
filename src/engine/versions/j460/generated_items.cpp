#include "engine/generated_items.h"
#include "engine/versions/j460/entrypoints.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include <MinHook.h>
#include <cstring>

namespace isaac::generated_items {
namespace {
using Address = std::uintptr_t;
Address image;
template <class T> const T& at(Address p, unsigned offset = 0) {
    return *reinterpret_cast<const T*>(p + offset);
}
using Generate = int(__attribute__((thiscall)) *)(void*, unsigned, unsigned);
Generate originalGenerate;
struct API {
    int(__cdecl* getTop)(lua_State*);
    const char*(__cdecl* checkString)(lua_State*, int, std::size_t*);
    long long(__cdecl* checkInteger)(lua_State*, int);
    void*(__cdecl* toUserdata)(lua_State*, int);
    std::size_t(__cdecl* rawLength)(lua_State*, int);
    void(__cdecl* pushInteger)(lua_State*, long long);
    const char*(__cdecl* pushString)(lua_State*, const char*, std::size_t);
    void(__cdecl* pushBoolean)(lua_State*, int);
    void(__cdecl* pushClosure)(lua_State*, int(__cdecl*)(lua_State*), int);
    void(__cdecl* setField)(lua_State*, int, const char*);
} lua;
int ownedCount(Address player, int id) {
    if (id >= 0 || id < -1024)
        throw std::runtime_error("Invalid generated item ID");
    // HasCollectible's negative-ID branch reads this native map. The ordinary
    // GetCollectibleNum entry instead rejects all negative IDs with zero.
    const auto head = at<Address>(player, 0x1fcc);
    const auto size = at<unsigned>(player, 0x1fd0);
    if (!head || size > 1024)
        throw std::runtime_error("Invalid generated inventory");
    auto node = at<Address>(head, 4);
    for (unsigned visited = 0; node != head; ++visited) {
        if (!node || visited >= size || at<unsigned char>(node, 0xd))
            throw std::runtime_error("Invalid generated inventory tree");
        const auto key = at<int>(node, 0x10), count = at<int>(node, 0x14);
        if (key >= 0 || key < -1024 || count < 0 || count > 65535)
            throw std::runtime_error("Invalid generated inventory entry");
        if (key == id)
            return count;
        node = at<Address>(node, id < key ? 0 : 8);
    }
    return 0;
}
int count(lua_State* L) {
    try {
        const auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
        const auto id = lua.checkInteger(L, 2);
        if (!wrapper || lua.rawLength(L, 1) != 8 || id >= 0 || id < -1024)
            throw std::runtime_error("Invalid generated inventory request");
        const auto game = at<Address>(image + engine::j460::globals::game);
        if (!game)
            throw std::runtime_error("Generated inventory requires a game");
        const auto first = at<Address>(game, 0x1baa8), last = at<Address>(game, 0x1baac);
        if (last < first || (last - first) % 4 || last - first > 32 * 4)
            throw std::runtime_error("Invalid native player roster");
        for (auto entry = first; entry < last; entry += 4) {
            const auto player = at<Address>(entry);
            if (player && wrapper[1] == player + 0x48 && at<unsigned>(player, 0x28) == 1) {
                lua.pushInteger(L, ownedCount(player, static_cast<int>(id)));
                return 1;
            }
        }
        throw std::runtime_error("Generated inventory requires a current player sprite");
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
Address registry() {
    const auto game = at<Address>(image + engine::j460::globals::game);
    if (!game)
        throw std::runtime_error("Generated items require a game");
    return game + 0x67758;
}
std::vector<unsigned> seeds(Address registry) {
    const auto first = at<Address>(registry), last = at<Address>(registry, 4);
    if (last < first || (last - first) % 4 || last - first > 1024 * 4)
        throw std::runtime_error("Invalid generated item registry");
    std::vector<unsigned> result;
    for (auto p = first; p < last; p += 4) {
        const auto entry = at<Address>(p);
        const auto config = entry ? at<Address>(entry) : 0;
        if (!config || at<int>(config, 4) != ~static_cast<int>(result.size()) ||
            !at<unsigned>(entry, 8))
            throw std::runtime_error("Invalid generated item definition");
        result.push_back(at<unsigned>(entry, 8));
    }
    return result;
}
int __attribute__((fastcall)) generate(void* self, void*, unsigned seed, unsigned flags) {
    // Replica room construction may roll pickups before its view is restored.
    // Only the authority may append definitions; the snapshot installs their
    // normalized seeds through the original generator, in native ID order.
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    if (runtime::replica() && caller != engine::j460::entry::generatedItemRestoreCall + 5)
        return (flags & 8) ? 105 : 25;
    return originalGenerate(self, seed, flags);
}
int state(lua_State* L) {
    try {
        const auto destination = registry();
        const auto current = seeds(destination);
        if (!lua.getTop(L)) {
            lan::Writer w(lan::Message::world);
            for (const auto seed : current)
                w.u32(seed);
            lua.pushString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                           w.bytes.size() - 1);
            return 1;
        }
        std::size_t size;
        const auto bytes = lua.checkString(L, 1, &size);
        if (!runtime::replica() || size % 4 || size > 4096)
            throw std::runtime_error("Invalid generated item snapshot");
        lan::Reader r({reinterpret_cast<const std::uint8_t*>(bytes), size});
        std::vector<unsigned> desired;
        for (std::size_t i = 0; i < size / 4; ++i) {
            const auto seed = r.u32();
            if (!seed || (i < current.size() && seed != current[i]))
                throw std::runtime_error("Generated item registry differs from authority");
            desired.push_back(seed);
        }
        if (current.size() > desired.size())
            throw std::runtime_error("Generated item registry is ahead of authority");
        // Native save restoration also replays normalized seeds with flags=0.
        // The game allocates/owns every config, effect list and sprite resource.
        for (auto i = current.size(); i < desired.size(); ++i)
            if (originalGenerate(reinterpret_cast<void*>(destination), desired[i], 0) !=
                ~static_cast<int>(i))
                throw std::runtime_error("Generated item restoration failed");
        lua.pushBoolean(L, true);
    } catch (const std::exception& error) {
        runtime::abort(error.what());
        lua.pushBoolean(L, false);
    }
    return 1;
}
} // namespace
bool install(std::uintptr_t base) {
    image = base;
    const auto target = reinterpret_cast<void*>(image + engine::j460::entry::generatedItemCreate);
    return MH_CreateHook(target, reinterpret_cast<void*>(generate),
                         reinterpret_cast<void**>(&originalGenerate)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
bool bind(lua_State* L, HMODULE module) {
#define IMPORT(field, name)                                                                        \
    do {                                                                                           \
        const auto pointer = GetProcAddress(module, name);                                         \
        static_assert(sizeof(pointer) == sizeof(lua.field));                                       \
        std::memcpy(&lua.field, &pointer, sizeof(pointer));                                        \
        if (!lua.field)                                                                            \
            return false;                                                                          \
    } while (false)
    IMPORT(getTop, "lua_gettop");
    IMPORT(checkString, "luaL_checklstring");
    IMPORT(checkInteger, "luaL_checkinteger");
    IMPORT(toUserdata, "lua_touserdata");
    IMPORT(rawLength, "lua_rawlen");
    IMPORT(pushInteger, "lua_pushinteger");
    IMPORT(pushString, "lua_pushlstring");
    IMPORT(pushBoolean, "lua_pushboolean");
    IMPORT(pushClosure, "lua_pushcclosure");
    IMPORT(setField, "lua_setfield");
#undef IMPORT
    lua.pushClosure(L, state, 0);
    lua.setField(L, -2, "generated_items");
    lua.pushClosure(L, count, 0);
    lua.setField(L, -2, "generated_item_count");
    return true;
}
} // namespace isaac::generated_items

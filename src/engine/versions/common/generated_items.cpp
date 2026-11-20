#include "engine/generated_items.h"
#include "engine/versions/common/generated_item_bindings.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include "engine/versions/common/hooks.h"
#include "engine/lua_api.h"
#include "compat/game_ids.h"

namespace isaac::generated_items {
namespace {
using Address = std::uintptr_t;
Address image;
template <class T> const T& at(Address p, unsigned offset = 0) {
    return *reinterpret_cast<const T*>(p + offset);
}
using Generate = int(__attribute__((thiscall)) *)(void*, unsigned, unsigned);
Generate originalGenerate;
using TriggerEffects = void(__attribute__((stdcall)) *)(int, void*, unsigned, void*, const void*,
                                                        const void*);
TriggerEffects originalTriggerEffects;
isaac::lua::API lua{};
using engine::native_generated_items::bindings;
bool installed;
constexpr unsigned maxOwnedCount = 65535, maxNativePlayers = 32;
constexpr unsigned wrapperBytes = 8, generateActiveFlag = 8;
constexpr unsigned callInstructionBytes = 5;
constexpr int passivePlaceholder = 25, activePlaceholder = 105;
int ownedCount(Address player, int id) {
    if (id >= 0 || id < -maxDefinitions)
        throw std::runtime_error("Invalid generated item ID");
    // HasCollectible's negative-ID branch reads this native quantity map;
    // ordinary static inventory enumeration does not cover its definitions.
    const auto head = at<Address>(player, bindings.layout.player.generatedInventoryHead);
    const auto size = at<unsigned>(player, bindings.layout.player.generatedInventorySize);
    if (!head || head % alignof(Address) || size > maxDefinitions)
        throw std::runtime_error("Invalid generated inventory");
    auto node = at<Address>(head, bindings.layout.inventoryNode.parent);
    for (unsigned visited = 0; node != head; ++visited) {
        if (!node || node % alignof(Address) || visited >= size ||
            at<unsigned char>(node, bindings.layout.inventoryNode.nil))
            throw std::runtime_error("Invalid generated inventory tree");
        const auto key = at<int>(node, bindings.layout.inventoryNode.id),
                   count = at<int>(node, bindings.layout.inventoryNode.count);
        if (key >= 0 || key < -maxDefinitions || count < 0 ||
            static_cast<unsigned>(count) > maxOwnedCount)
            throw std::runtime_error("Invalid generated inventory entry");
        if (key == id)
            return count;
        node = at<Address>(node, id < key ? bindings.layout.inventoryNode.left
                                          : bindings.layout.inventoryNode.right);
    }
    return 0;
}
int count(lua_State* L) {
    try {
        const auto wrapper = static_cast<Address*>(lua.toUserdata(L, 1));
        const auto id = lua.checkInteger(L, 2);
        if (!wrapper || lua.rawLength(L, 1) != wrapperBytes || id >= 0 || id < -maxDefinitions)
            throw std::runtime_error("Invalid generated inventory request");
        const auto game = at<Address>(image + bindings.game);
        if (!game)
            throw std::runtime_error("Generated inventory requires a game");
        const auto first = at<Address>(game,
                                       bindings.layout.game.players + bindings.layout.vector.begin),
                   last =
                       at<Address>(game, bindings.layout.game.players + bindings.layout.vector.end);
        if ((!first && first != last) || first % alignof(Address) || last < first ||
            (last - first) % sizeof(Address) || last - first > maxNativePlayers * sizeof(Address))
            throw std::runtime_error("Invalid native player roster");
        for (auto entry = first; entry < last; entry += 4) {
            const auto player = at<Address>(entry);
            if (player && wrapper[1] == player + bindings.layout.entity.sprite &&
                at<unsigned>(player, bindings.layout.entity.type) == 1) {
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
    const auto game = at<Address>(image + bindings.game);
    if (!game)
        throw std::runtime_error("Generated items require a game");
    return game + bindings.layout.game.generatedItems;
}
std::vector<unsigned> seeds(Address registry) {
    const auto first = at<Address>(registry, bindings.layout.vector.begin),
               last = at<Address>(registry, bindings.layout.vector.end);
    if ((!first && first != last) || first % alignof(Address) || last < first ||
        (last - first) % sizeof(Address) || last - first > maxPayloadBytes)
        throw std::runtime_error("Invalid generated item registry");
    std::vector<unsigned> result;
    for (auto p = first; p < last; p += 4) {
        const auto entry = at<Address>(p);
        const auto config = entry ? at<Address>(entry, bindings.layout.generatedItem.config) : 0;
        if (!config ||
            at<int>(config, bindings.layout.generatedItem.configId) !=
                ~static_cast<int>(result.size()) ||
            !at<unsigned>(entry, bindings.layout.generatedItem.seed))
            throw std::runtime_error("Invalid generated item definition");
        result.push_back(at<unsigned>(entry, bindings.layout.generatedItem.seed));
    }
    return result;
}
int __attribute__((fastcall)) generate(void* self, void*, unsigned seed, unsigned flags) {
    // Replica room construction may roll pickups before its view is restored.
    // Only the authority may append definitions; the snapshot installs their
    // normalized seeds through the original generator, in native ID order.
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    if (runtime::replica() && caller != bindings.entry.restoreCall + callInstructionBytes)
        return (flags & generateActiveFlag) ? activePlaceholder : passivePlaceholder;
    return originalGenerate(self, seed, flags);
}
void __attribute__((stdcall)) triggerEffects(int id, void* player, unsigned event, void* entity,
                                             const void* position, const void* velocity) {
    // Restoring a replica can spawn entities and rebuild player inventories.
    // Generated event chains must not run gameplay again during that work or
    // during local presentation updates; their results come from the authority.
    if (!runtime::replica())
        originalTriggerEffects(id, player, event, entity, position, velocity);
}
int state(lua_State* L) {
    try {
        const auto destination = registry();
        const auto current = seeds(destination);
        if (!lua.getTop(L)) {
            lan::Writer w(lan::Message::world);
            for (const auto seed : current)
                w.u32(seed);
            lua.pushLString(L, reinterpret_cast<const char*>(w.bytes.data() + 1),
                            w.bytes.size() - 1);
            return 1;
        }
        std::size_t size;
        const auto bytes = lua.checkString(L, 1, &size);
        if (!runtime::replica() || size % 4 || size > maxPayloadBytes)
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
    if (!base || installed)
        return false;
    image = base;
    engine::native_hooks::Group<2> hooks;
    if (hooks.add(image + bindings.entry.create, generate, originalGenerate) &&
        hooks.add(image + bindings.entry.trigger, triggerEffects, originalTriggerEffects) &&
        hooks.enable()) {
        installed = true;
        return true;
    }
    originalGenerate = nullptr;
    originalTriggerEffects = nullptr;
    image = 0;
    return false;
}
bool bind(lua_State* L, HMODULE module) {
    using S = isaac::lua::Symbol;
    if (!lua.load(module,
                  {S::getTop, S::checkString, S::checkInteger, S::toUserdata, S::rawLength,
                   S::pushInteger, S::pushLString, S::pushBoolean, S::pushClosure, S::setField}))
        return false;
    lua.pushClosure(L, state, 0);
    lua.setField(L, -2, "generated_items");
    lua.pushClosure(L, count, 0);
    lua.setField(L, -2, "generated_item_count");
    return true;
}
} // namespace isaac::generated_items

#include "engine/versions/j460/cursed_mist.h"
#include "engine/versions/j460/layout.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include <MinHook.h>
#include <cstddef>

namespace isaac::engine::j460::cursed_mist {
namespace {
static_assert(sizeof(QueryResult) == 16 && offsetof(QueryResult, data) == 4 &&
              offsetof(QueryResult, count) == 12);
Address image;
FamiliarQueries queries;
using PlayerCall = void(__attribute__((thiscall)) *)(void*);
using Find = QueryResult*(__attribute__((thiscall)) *)(void*, QueryResult*, int, int, int, bool,
                                                       bool);
PlayerCall originalDisable, originalEnable;
Find originalFind;
void withOwner(void* player, PlayerCall action) {
    const auto owner =
        rooms::virtualized() && !runtime::replica() ? reinterpret_cast<Address>(player) : 0;
    queries.withOwner(owner, [&] { action(player); });
}
void __attribute__((fastcall)) disable(void* player, void*) {
    withOwner(player, originalDisable);
}
void __attribute__((fastcall)) enable(void* player, void*) {
    withOwner(player, originalEnable);
}
QueryResult* __attribute__((fastcall)) find(void* list, void*, QueryResult* buffer, int type,
                                            int variant, int subtype, bool cache,
                                            bool ignoreFriendly) {
    const auto caller = reinterpret_cast<Address>(__builtin_return_address(0)) - image;
    auto result = originalFind(list, buffer, type, variant, subtype, cache, ignoreFriendly);
    if (result)
        queries.filter(*result, caller, type, variant, subtype, cache, ignoreFriendly,
                       [](Address familiar) {
                           return *reinterpret_cast<Address*>(familiar + layout::familiar::player);
                       });
    return result;
}
} // namespace
bool install(Address base) {
    image = base;
    auto hook = [&](unsigned entry, auto replacement, auto& original) {
        auto target = reinterpret_cast<void*>(image + entry);
        return MH_CreateHook(target, reinterpret_cast<void*>(replacement),
                             reinterpret_cast<void**>(&original)) == MH_OK &&
               MH_EnableHook(target) == MH_OK;
    };
    return hook(entry::entityListFindByType, find, originalFind) &&
           hook(entry::playerDisableCollectibles, disable, originalDisable) &&
           hook(entry::playerEnableCollectibles, enable, originalEnable);
}
} // namespace isaac::engine::j460::cursed_mist

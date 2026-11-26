#include "engine/versions/common/frontend_hud.h"
#include "engine/versions/common/frontend_hud_bindings.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include "net/protocol.h"
#include "compat/game_ids.h"
#include <MinHook.h>
#include <array>
#include <cmath>
namespace isaac::engine::native_frontend_hud {
namespace {
using Address = std::uintptr_t;
using MenuUpdate = void(__attribute__((thiscall)) *)(void*);
Address image = 0;
bool installed = false;
struct ComponentFilter {
    Filter mask;
    Renderer draw = nullptr;
};
std::array<ComponentFilter, names.size()> filters{};
template <class T> T& read(Address object, unsigned offset) {
    return *reinterpret_cast<T*>(object + offset);
}
using StatPlayerId = int(__attribute__((thiscall)) *)(void*, void*);
StatPlayerId originalStatPlayerId = nullptr;
int __attribute__((fastcall)) statPlayerId(void* hud, void*, void* player) {
    const int slot = runtime::localViewSlot();
    if (slot < 0)
        return originalStatPlayerId(hud, player);
    if (!hud || !player)
        return -1;
    const auto address = reinterpret_cast<std::uintptr_t>(hud);
    // StatHUD owns two scalar stat caches (Jacob and Esau). Clear a stale
    // teammate cache from the pre-network startup before selecting our actor.
    for (unsigned i = 0; i < bindings.stats.cacheCount; ++i) {
        const auto cached = *reinterpret_cast<std::uintptr_t*>(address + bindings.stats.player +
                                                               i * bindings.stats.cacheStride);
        if (cached && *reinterpret_cast<int*>(cached + bindings.player.controller) != slot + 1) {
            using Reset = void(__attribute__((thiscall))*)(void*);
            reinterpret_cast<Reset>(image + bindings.entry.frontendStatHUDReset)(hud);
            break;
        }
    }
    if (*reinterpret_cast<int*>(reinterpret_cast<std::uintptr_t>(player) +
                                bindings.player.controller) != slot + 1)
        return -1;
    return originalStatPlayerId(hud, player);
}
MenuUpdate originalHudUpdate = nullptr, originalHudPostUpdate = nullptr,
           originalHudRender = nullptr;
StatPlayerId originalHistoryPlayerId = nullptr;
int __attribute__((fastcall)) historyPlayerId(void* history, void*, void* player) {
    const int slot = runtime::localViewSlot();
    if (slot < 0)
        return originalHistoryPlayerId(history, player);
    if (!history || !player)
        return -1;
    if (read<int>(reinterpret_cast<std::uintptr_t>(player), bindings.player.controller) != slot + 1)
        return -1;
    int result = -1;
    rooms::withView([&] { result = originalHistoryPlayerId(history, player); }, true);
    return result;
}
void bindTeamHud(void* hud) {
    const int slot = runtime::localViewSlot();
    if (slot < 0)
        return;
    const auto game = read<std::uintptr_t>(image, bindings.game),
               address = reinterpret_cast<std::uintptr_t>(hud);
    if (!game || !hud)
        return;
    std::array<std::uintptr_t, lan::maxPlayers * 2> desired{};
    unsigned ordinal = 0;
    for (auto entry = read<std::uintptr_t>(game, bindings.players);
         entry < read<std::uintptr_t>(game, bindings.players + sizeof(Address)) &&
         ordinal < lan::maxPlayers;
         entry += sizeof(std::uintptr_t)) {
        const auto p = read<std::uintptr_t>(entry, 0);
        if (!p)
            continue;
        if (read<int>(p, bindings.entity.parent) != 0 || !read<bool>(p, bindings.entity.active))
            continue;
        const auto twin = read<std::uintptr_t>(p, bindings.player.twin);
        if (twin && twin != p && read<int>(twin, bindings.player.index) >= 0 &&
            read<int>(twin, bindings.player.index) < read<int>(p, bindings.player.index))
            continue;
        desired[ordinal] = p;
        if (twin && twin != p && read<bool>(twin, bindings.entity.active) &&
            read<int>(twin, bindings.player.type) != compat::ids::player::soulB)
            desired[ordinal + lan::maxPlayers] = twin;
        ++ordinal;
    }
    bool changed = false;
    for (unsigned i = 0; i < desired.size(); ++i) {
        const auto part = address + i * bindings.playerHud.size;
        if (read<std::uintptr_t>(part, 0) == desired[i])
            continue;
        // Reset owned caches through the native destructor/reset routine. A
        // pointer-only swap leaves heart and inventory caches from a teammate.
        reinterpret_cast<MenuUpdate>(image +
                                     bindings.entry.playerHUDReset)(reinterpret_cast<void*>(part));
        read<std::uintptr_t>(part, 0) = desired[i];
        read<unsigned short>(part, bindings.playerHud.refreshFlags) = bindings.playerHud.refreshAll;
        changed = true;
    }
    if (changed) {
        using Recompute = void(__attribute__((thiscall))*)(void*, bool);
        reinterpret_cast<Recompute>(image + bindings.entry.historyHUDRecomputeAll)(
            reinterpret_cast<void*>(address + bindings.history), true);
    }
}
void __attribute__((fastcall)) hudUpdate(void* hud, void*) {
    rooms::withView([&] { originalHudUpdate(hud); });
}
void __attribute__((fastcall)) hudPostUpdate(void* hud, void*) {
    rooms::withView([&] {
        bindTeamHud(hud);
        originalHudPostUpdate(hud);
    });
}
void __attribute__((fastcall)) hudRender(void* hud, void*) {
    rooms::withView([&] {
        bindTeamHud(hud);
        originalHudRender(hud);
    });
}

} // namespace
void configure(Component component, Filter filter, Renderer draw) {
    filters[static_cast<unsigned>(component)] = {filter, draw};
}
void resetFilters() {
    filters = {};
}
bool replace(Component component, void* hud, const Draw& draw) {
    const auto [filter, renderer] = filters[static_cast<unsigned>(component)];
    if ((!filter.hidden && !filter.rendered) || !hud || !image)
        return false;
    const int slot = runtime::localViewSlot();
    const auto player = read<Address>(reinterpret_cast<Address>(hud), 0);
    if (slot < 0 || !player)
        return false;
    const auto controller = read<int>(player, bindings.player.controller);
    if (controller < 1 || controller > static_cast<int>(lan::maxPlayers))
        return false;
    constexpr unsigned local = 1, teammates = 2;
    const auto audience = controller == slot + 1 ? local : teammates;
    if (filter.hidden & audience)
        return true;
    if (!(filter.rendered & audience) || !renderer || !std::isfinite(draw.position.x) ||
        !std::isfinite(draw.position.y) || !std::isfinite(draw.scale) || draw.scale == 0 ||
        !std::isfinite(draw.alpha))
        return false;
    // Isaac.GetPlayer indexes the current render roster (local bodies first).
    const auto game = read<Address>(image, bindings.game);
    if (!game)
        return false;
    const auto begin = read<Address>(game, bindings.players);
    const auto end = read<Address>(game, bindings.players + sizeof(Address));
    for (auto entry = begin; entry < end; entry += sizeof(Address))
        if (read<Address>(entry, 0) == player)
            return renderer(component, (entry - begin) / sizeof(Address), draw);
    return false;
}
bool install(Address base) {
    if (!base || installed)
        return false;
    struct Hook {
        unsigned rva;
        void* detour;
        void** original;
    };
    const std::array<Hook, 8> hooks{{
        {bindings.entry.statPlayerId, reinterpret_cast<void*>(statPlayerId),
         reinterpret_cast<void**>(&originalStatPlayerId)},
        {bindings.entry.historyPlayerId, reinterpret_cast<void*>(historyPlayerId),
         reinterpret_cast<void**>(&originalHistoryPlayerId)},
        {bindings.entry.update, reinterpret_cast<void*>(hudUpdate),
         reinterpret_cast<void**>(&originalHudUpdate)},
        {bindings.entry.postUpdate, reinterpret_cast<void*>(hudPostUpdate),
         reinterpret_cast<void**>(&originalHudPostUpdate)},
        {bindings.entry.render, reinterpret_cast<void*>(hudRender),
         reinterpret_cast<void**>(&originalHudRender)},
        {bindings.entry.hearts, heartHook.detour, heartHook.original},
        {bindings.entry.activeItem, activeItemHook.detour, activeItemHook.original},
        {bindings.entry.trinket, trinketHook.detour, trinketHook.original},
    }};
    image = base;
    unsigned created = 0;
    const auto rollback = [&] {
        for (unsigned i = 0; i < created; ++i) {
            MH_RemoveHook(reinterpret_cast<void*>(image + hooks[i].rva));
            *hooks[i].original = nullptr;
        }
        image = 0;
    };
    for (const auto& hook : hooks) {
        if (MH_CreateHook(reinterpret_cast<void*>(image + hook.rva), hook.detour, hook.original) !=
            MH_OK) {
            rollback();
            return false;
        }
        ++created;
    }
    for (const auto& hook : hooks)
        if (MH_EnableHook(reinterpret_cast<void*>(image + hook.rva)) != MH_OK) {
            rollback();
            return false;
        }
    installed = true;
    return true;
}
} // namespace isaac::engine::native_frontend_hud

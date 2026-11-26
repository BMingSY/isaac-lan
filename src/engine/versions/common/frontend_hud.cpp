#include "engine/versions/common/player_seats.h"
#include "engine/versions/common/frontend_hud.h"
#include "engine/versions/common/frontend_hud_bindings.h"
#include "engine/versions/common/player_hud.h"
#include "engine/rooms.h"
#include "runtime/session.h"
#include "compat/game_ids.h"
#include <MinHook.h>
#include <array>
namespace isaac::engine::native_frontend_hud {
namespace {
using Address = std::uintptr_t;
using MenuUpdate = void(__attribute__((thiscall)) *)(void*);
Address image = 0;
bool installed = false;
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
        if (cached && player_seats::owner(cached, read<int>(cached, bindings.player.controller)) !=
                          slot + 1) {
            using Reset = void(__attribute__((thiscall))*)(void*);
            reinterpret_cast<Reset>(image + bindings.entry.frontendStatHUDReset)(hud);
            break;
        }
    }
    if (player_seats::owner(
            reinterpret_cast<Address>(player),
            read<int>(reinterpret_cast<Address>(player), bindings.player.controller)) != slot + 1)
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
    if (player_seats::owner(
            reinterpret_cast<Address>(player),
            read<int>(reinterpret_cast<Address>(player), bindings.player.controller)) != slot + 1)
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
    std::array<std::uintptr_t, native_player_hud::totalPanels> desired{};
    unsigned ordinal = 0;
    for (auto entry = read<std::uintptr_t>(game, bindings.players);
         entry < read<std::uintptr_t>(game, bindings.players + sizeof(Address)) &&
         ordinal < native_player_hud::primaryPanels;
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
            desired[ordinal + native_player_hud::primaryPanels] = twin;
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
    const bool personal = native_player_hud::localOnly(rooms::connected());
    rooms::withView(
        [&] {
            if (personal)
                bindTeamHud(hud);
            originalHudUpdate(hud);
        },
        personal);
}
void __attribute__((fastcall)) hudPostUpdate(void* hud, void*) {
    rooms::withView(
        [&] {
            bindTeamHud(hud);
            originalHudPostUpdate(hud);
        },
        native_player_hud::localOnly(rooms::connected()));
}
void __attribute__((fastcall)) hudRender(void* hud, void*) {
    rooms::withView(
        [&] {
            bindTeamHud(hud);
            originalHudRender(hud);
        },
        native_player_hud::localOnly(rooms::connected()));
}

} // namespace
bool install(Address base) {
    if (!base || installed)
        return false;
    struct Hook {
        unsigned rva;
        void* detour;
        void** original;
    };
    const std::array<Hook, 5> hooks{{
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

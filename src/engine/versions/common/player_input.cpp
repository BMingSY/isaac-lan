#include "engine/versions/common/player_input.h"
#include "engine/versions/common/player_seats.h"

namespace isaac::engine::native_players {
namespace {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
constexpr unsigned maxNativeActors = 256, maxPlayerType = 65535;
constexpr float spawnSpacing = 12;
template <class T> T& at(Address address, unsigned offset = 0) {
    return *reinterpret_cast<T*>(address + offset);
}
Address game(Address image) {
    return image ? at<Address>(image, bindings.game) : 0;
}
bool validController(int controller) {
    return player_seats::device(controller) != 0;
}
struct Roster {
    Address begin;
    unsigned count;
    Address player(unsigned slot) const {
        return slot < count ? at<Address>(begin, slot * sizeof(Address)) : 0;
    }
};
std::optional<Roster> roster(Address g) {
    if (!g)
        return {};
    const auto begin = at<Address>(g, bindings.players),
               end = at<Address>(g, bindings.players + sizeof(Address)),
               capacity = at<Address>(g, bindings.players + 2 * sizeof(Address));
    if (!begin || end < begin || capacity < end || (end - begin) % sizeof(Address) ||
        (capacity - begin) % sizeof(Address) || (end - begin) / sizeof(Address) > maxNativeActors)
        return {};
    return Roster{begin, (end - begin) / sizeof(Address)};
}
void assignPlayer(Address image, Address player, int controller) {
    using Assign = void(__attribute__((thiscall))*)(void*, int, bool);
    reinterpret_cast<Assign>(image + bindings.assign)(reinterpret_cast<void*>(player), controller,
                                                      true);
}
} // namespace
bool assign(Address image, unsigned slot, int controller) {
    if (!validController(controller))
        return false;
    const auto players = roster(game(image));
    const auto player = players ? players->player(slot) : 0;
    if (!player)
        return false;
    const auto device = player_seats::device(controller);
    assignPlayer(image, player, device);
    if (at<int>(player, bindings.controller) != device)
        return false;
    player_seats::bind(player, controller, bindings.initSeed);
    if (controller > player_seats::nativeGamepads) {
        // Continue restores a native roster before assigning its LAN seats.
        // A companion may precede its owner and share a device with another head.
        for (unsigned i = 0; i < players->count; ++i) {
            const auto body = players->player(i);
            if (body && body != player &&
                (at<Address>(body, bindings.parent) == player ||
                 at<Address>(body, bindings.twin) == player ||
                 at<Address>(player, bindings.twin) == body ||
                 at<Address>(player, bindings.lazarusBackup) == body))
                player_seats::bind(body, controller, bindings.initSeed);
        }
    }
    return true;
}
std::optional<unsigned> spawn(Address image, int type, int controller,
                              void (*onInitialized)(void*, unsigned)) {
    if (type < 0 || static_cast<unsigned>(type) > maxPlayerType || !validController(controller))
        return {};
    const auto g = game(image);
    const auto before = roster(g);
    if (!before || !before->player(0))
        return {};
    using Spawn = void*(__attribute__((thiscall))*)(void*, int);
    const auto result = reinterpret_cast<Spawn>(image + bindings.spawn)(
        reinterpret_cast<void*>(g + bindings.manager), type);
    if (!result || game(image) != g)
        return {};
    const auto created = roster(g);
    if (!created || created->player(before->count) != reinterpret_cast<Address>(result))
        return {};
    const auto device = player_seats::device(controller);
    assignPlayer(image, reinterpret_cast<Address>(result), device);
    player_seats::bind(reinterpret_cast<Address>(result), controller, bindings.initSeed);
    using Call = void(__attribute__((thiscall))*)(void*);
    reinterpret_cast<Call>(image + bindings.initialize)(result);
    if (game(image) != g)
        return {};
    if (onInitialized)
        onInitialized(result, static_cast<unsigned>(controller - 1));
    if (game(image) != g)
        return {};
    // Reacquire after initialization and rewards: either can append companions
    // or relocate the vector. No iterator from the old allocation survives.
    const auto after = roster(g);
    if (!after || !after->player(0) || after->count <= before->count)
        return {};
    for (auto slot = before->count; slot < after->count; ++slot)
        if (!after->player(slot))
            return {};
    const auto first = after->player(0);
    for (auto slot = before->count; slot < after->count; ++slot) {
        const auto player = after->player(slot);
        assignPlayer(image, player, device);
        player_seats::bind(player, controller, bindings.initSeed);
        at<float>(player, bindings.positionX) = at<float>(player, bindings.previousX) =
            at<float>(first, bindings.positionX) + spawnSpacing * controller;
        at<float>(player, bindings.positionY) = at<float>(player, bindings.previousY) =
            at<float>(first, bindings.positionY);
    }
    // The personal HUD binds its own panels on update. Never assign the
    // full expanded party to the game's four primary HUD panels.
    if (!player_seats::additional.empty())
        return before->count;
    using GetHUD = void*(__attribute__((thiscall))*)(void*);
    const auto hud = reinterpret_cast<GetHUD>(image + bindings.getHUD)(reinterpret_cast<void*>(g));
    if (!hud)
        return {};
    reinterpret_cast<Call>(image + bindings.assignHUDs)(hud);
    return before->count;
}
} // namespace isaac::engine::native_players

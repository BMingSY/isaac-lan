#include "test_support.h"
#include "native_call.h"
#include "engine/versions/common/frontend_hud.cpp"
#include "runtime/actor_roster.h"
#include <cstring>
#include <iostream>
#include <vector>
#ifdef ISAAC_LAN_TEST_REPENTANCE
constexpr unsigned gameGlobal = 0x7fd65c, playersOffset = 0x1ba50, historyOffset = 0xc45c4;
constexpr unsigned controllerOffset = 0x154c, indexOffset = 0x1550, twinOffset = 0x1d80,
                   kindOffset = 0x130c, parentOffset = 0x314, activeOffset = 0x16a;
constexpr unsigned partSize = 0x6b0, refreshOffset = 0x6a0;
constexpr std::array<unsigned, 8> entries{0x508370, 0x508400, 0x508000, 0x507c90,
                                          0x4f9780, 0x5027e0, 0x502a20, 0x504610};
#else
constexpr unsigned gameGlobal = 0x8994f8, playersOffset = 0x1baa8, historyOffset = 0x5c54;
constexpr unsigned controllerOffset = 0x161c, indexOffset = 0x1620, twinOffset = 0x1e68,
                   kindOffset = 0x13c4, parentOffset = 0x3bc, activeOffset = 0x172;
constexpr unsigned partSize = 0x6dc, refreshOffset = 0x6ac;
constexpr std::array<unsigned, 8> entries{0x454b50, 0x454bf0, 0x444590, 0x444220,
                                          0x44aa10, 0x5b9a50, 0x5b9bf0, 0x5bae80};
#endif
namespace {
namespace view = isaac::engine::native_frontend_hud;
using Address = std::uintptr_t;
unsigned char* image = nullptr;
void* expectedHud = nullptr;
int localSlot = -1;
unsigned connectedMask = 0xf;
bool expectPersonalHud = false;
unsigned depth = 0, localDepth = 0, statQueries = 0, statResets = 0, historyQueries = 0,
         historyRefreshes = 0, renders = 0, updates = 0, postUpdates = 0;
std::array<unsigned, 8> resets{}, resources{};
bool failRender = false;
template <class T> T& field(void* object, unsigned offset) {
    return *reinterpret_cast<T*>(static_cast<unsigned char*>(object) + offset);
}
Address address(const void* value) {
    return reinterpret_cast<Address>(value);
}
void jump(unsigned char* entry, void* function) {
    std::memset(entry, 0x90, 16);
    entry[0] = 0xe9;
    auto delta = address(function) - address(entry + 5);
    std::memcpy(entry + 1, &delta, 4);
}
int __attribute__((fastcall)) statNative(void* stats, void*, void* player) {
    ++statQueries;
    field<Address>(stats, 0x114) = address(player);
    return 1;
}
void __attribute__((fastcall)) resetStats(void* stats, void*) {
    ++statResets;
    field<Address>(stats, 0x114) = field<Address>(stats, 0x114 + 0xcc) = 0;
}
int __attribute__((fastcall)) historyNative(void*, void*, void*) {
    require(localSlot < 0 || (depth && localDepth), "History query lost its local player scope");
    ++historyQueries;
    return 7;
}
void __attribute__((fastcall)) recomputeHistory(void* history, void*, bool force) {
    require(address(history) == address(expectedHud) + historyOffset && force && depth,
            "History recompute used wrong object, argument or view");
    ++historyRefreshes;
}
void __attribute__((fastcall)) resetPlayerHud(void* part, void*) {
    const auto offset = address(part) - address(expectedHud);
    require(offset % partSize == 0 && offset / partSize < 8,
            "PlayerHUD Reset used the wrong native stride");
    const auto index = offset / partSize;
    require(field<Address>(part, 4) == address(expectedHud), "PlayerHUD lost its owning HUD");
    resources[index] = 0;
    ++resets[index];
    field<Address>(part, 0) = 0;
    field<unsigned short>(part, refreshOffset) = 0;
}
void __attribute__((fastcall)) updateNative(void* hud, void*) {
    require(hud == expectedHud && depth, "HUD update escaped the room view");
    require(bool(localDepth) == expectPersonalHud, "HUD update used the wrong audience");
    ++updates;
}
void __attribute__((fastcall)) postNative(void* hud, void*) {
    require(hud == expectedHud && depth, "HUD post-update escaped the room view");
    require(bool(localDepth) == expectPersonalHud, "HUD post-update used the wrong audience");
    ++postUpdates;
}
void __attribute__((fastcall)) renderNative(void* hud, void*) {
    require(hud == expectedHud && depth, "HUD render escaped the room view");
    require(bool(localDepth) == expectPersonalHud, "HUD render used the wrong audience");
    ++renders;
    if (failRender)
        throw std::runtime_error("Fixture HUD rendering failure");
}
void installHooks() {
    const std::array<void*, 8> functions{
        reinterpret_cast<void*>(statNative),     reinterpret_cast<void*>(resetStats),
        reinterpret_cast<void*>(historyNative),  reinterpret_cast<void*>(recomputeHistory),
        reinterpret_cast<void*>(resetPlayerHud), reinterpret_cast<void*>(updateNative),
        reinterpret_cast<void*>(postNative),     reinterpret_cast<void*>(renderNative)};
    for (unsigned i = 0; i < entries.size(); ++i)
        jump(image + entries[i], functions[i]);
    FlushInstructionCache(GetCurrentProcess(), image, privateGameImageBytes);
    require(!view::install(0), "Null image installed frontend HUD hooks");
    const std::array<unsigned, 5> hooks{entries[0], entries[2], entries[5], entries[6], entries[7]};
    for (unsigned conflict = 0; conflict < hooks.size(); ++conflict) {
        auto* target = image + hooks[conflict];
        require(MH_CreateHook(target, functions[0], nullptr) == MH_OK, "Create foreign HUD hook");
        require(!view::install(address(image)) && !view::installed && !view::image,
                "Partial frontend HUD install survived failure");
        require(MH_CreateHook(target, functions[0], nullptr) == MH_ERROR_ALREADY_CREATED,
                "HUD rollback removed another component's hook");
        for (unsigned i = 0; i < conflict; ++i) {
            require(MH_CreateHook(image + hooks[i], functions[0], nullptr) == MH_OK,
                    "HUD rollback retained an earlier owned hook");
            require(MH_RemoveHook(image + hooks[i]) == MH_OK, "Remove HUD rollback probe");
        }
        require(MH_RemoveHook(target) == MH_OK, "Remove foreign HUD fixture");
    }
    require(view::install(address(image)) && !view::install(address(image)),
            "HUD installation retry or duplicate guard failed");
}
} // namespace
namespace isaac::runtime {
int localViewSlot() {
    return localSlot;
}
} // namespace isaac::runtime
namespace isaac::rooms {
unsigned connected() {
    return connectedMask;
}
void withView(const std::function<void()>& render, bool localOnly) {
    struct Restore {
        unsigned depth = ::depth, local = localDepth;
        ~Restore() {
            ::depth = depth;
            localDepth = local;
        }
    } restore;
    ++depth;
    if (localOnly) {
        ++localDepth;
        const auto game = field<Address>(image, gameGlobal);
        if (game) {
            auto& begin = field<Address>(reinterpret_cast<void*>(game), playersOffset);
            auto& end =
                field<Address>(reinterpret_cast<void*>(game), playersOffset + sizeof(Address));
            auto* first = reinterpret_cast<Address*>(begin);
            auto* last = reinterpret_cast<Address*>(end);
            std::vector<Address> selected(first, last);
            actors::selectView(selected, true, [&](Address p) {
                return p &&
                       field<int>(reinterpret_cast<void*>(p), controllerOffset) == localSlot + 1;
            });
            struct RestoreRoster {
                Address& begin;
                Address& end;
                Address savedBegin, savedEnd;
                ~RestoreRoster() {
                    begin = savedBegin;
                    end = savedEnd;
                }
            } restoreRoster{begin, end, begin, end};
            begin = address(selected.data());
            end = begin + selected.size() * sizeof(Address);
            render();
            return;
        }
    }
    render();
}
} // namespace isaac::rooms
int main() {
    try {
        image = static_cast<unsigned char*>(VirtualAlloc(
            nullptr, privateGameImageBytes, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE));
        require(image && MH_Initialize() == MH_OK, "Allocate frontend HUD fixture");
        installHooks();
        std::vector<unsigned char> game(0x1bc00), hud(historyOffset + 0x100, 0xa5);
        std::array<std::array<unsigned char, 0x2100>, 5> players{};
        expectedHud = hud.data();
        field<Address>(image, gameGlobal) = address(game.data());
        for (unsigned i = 0; i < players.size(); ++i) {
            field<int>(players[i].data(), controllerOffset) = i + 1;
            field<int>(players[i].data(), indexOffset) = i;
            field<bool>(players[i].data(), activeOffset) = true;
        }
        field<Address>(players[1].data(), twinOffset) = address(players[2].data());
        field<Address>(players[2].data(), twinOffset) = address(players[1].data());
        field<int>(players[2].data(), controllerOffset) = 2;
        field<Address>(players[3].data(), parentOffset) = address(players[1].data());
        field<bool>(players[4].data(), activeOffset) = false;
        std::vector<Address> roster{address(players[0].data()), address(players[2].data()),
                                    address(players[1].data()), address(players[3].data()),
                                    address(players[4].data()), 0};
        const auto setRoster = [&] {
            field<Address>(game.data(), playersOffset) = address(roster.data());
            field<Address>(game.data(), playersOffset + 4) = address(roster.data() + roster.size());
        };
        setRoster();
        for (unsigned i = 0; i < 8; ++i) {
            auto* part = hud.data() + i * partSize;
            field<Address>(part, 0) = address(players[4].data());
            field<Address>(part, 4) = address(hud.data());
            resources[i] = i + 1;
        }
        const auto initialHud = hud;
        using Update = void(__attribute__((thiscall))*)(void*);
        const auto callHud = [&](unsigned index) {
            reinterpret_cast<Update>(image + entries[index])(hud.data());
        };
        callHud(7);
        require(hud == initialHud && renders == 1 && !depth,
                "Offline HUD render rebound native players");
        localSlot = 1;
        callHud(5);
        require(hud == initialHud && updates == 1, "Early HUD update changed roster ownership");
        callHud(6);
        auto expected = initialHud;
        const std::array<Address, 8> expectedPlayers{address(players[0].data()),
                                                     address(players[1].data()),
                                                     0,
                                                     0,
                                                     0,
                                                     address(players[2].data()),
                                                     0,
                                                     0};
        for (unsigned i = 0; i < 8; ++i) {
            field<Address>(expected.data(), i * partSize) = expectedPlayers[i];
            field<unsigned short>(expected.data(), i * partSize + refreshOffset) = 0x101;
            require(resets[i] == 1 && resources[i] == 0, "HUD binding bypassed native cache reset");
        }
        require(hud == expected && historyRefreshes == 1 && postUpdates == 1 && !depth,
                "Team HUD wrote unrelated state, selected children or duplicated a twin");
        callHud(7);
        require(resets == std::array<unsigned, 8>{1, 1, 1, 1, 1, 1, 1, 1} &&
                    historyRefreshes == 1 && hud == expected,
                "Repeated HUD binding reset owned caches again");
        roster = {address(players[1].data()), address(players[0].data())};
        setRoster();
        callHud(7);
        require(field<Address>(hud.data(), 0) == address(players[1].data()) &&
                    field<Address>(hud.data(), partSize) == address(players[0].data()) &&
                    field<Address>(hud.data(), 4 * partSize) == address(players[2].data()) &&
                    field<Address>(hud.data(), 5 * partSize) == 0 && historyRefreshes == 2,
                "Local-first reordered HUD kept the previous player's caches");
        field<int>(players[2].data(), kindOffset) = 40;
        callHud(6);
        require(field<Address>(hud.data(), 4 * partSize) == 0 && historyRefreshes == 3,
                "Soul B occupied the twin HUD row");
        failRender = true;
        try {
            callHud(7);
            require(false, "Fixture HUD exception did not propagate");
        } catch (const std::runtime_error& error) {
            require(std::string(error.what()) == "Fixture HUD rendering failure",
                    "Unexpected HUD render failure");
        }
        require(!depth && !localDepth, "Failed HUD draw retained the room view");
        failRender = false;
        roster.clear();
        setRoster();
        callHud(6);
        for (unsigned i = 0; i < 8; ++i)
            require(field<Address>(hud.data(), i * partSize) == 0,
                    "Disconnected actor remained in the team HUD");

        std::array<std::array<unsigned char, 0x2100>, 6> largeParty{};
        for (unsigned i = 0; i < largeParty.size(); ++i) {
            auto* player = largeParty[i].data();
            field<bool>(player, activeOffset) = true;
            field<int>(player, controllerOffset) = static_cast<int>(std::min(i + 1, 5u));
            field<int>(player, indexOffset) = i;
            roster.push_back(address(player));
        }
        field<Address>(largeParty[4].data(), twinOffset) = address(largeParty[5].data());
        field<Address>(largeParty[5].data(), twinOffset) = address(largeParty[4].data());
        setRoster();
        connectedMask = 0x1f;
        expectPersonalHud = true;
        for (localSlot = 0; localSlot < 5; ++localSlot) {
            callHud(5);
            callHud(6);
            callHud(7);
            for (unsigned i = 0; i < 8; ++i) {
                const auto expectedPlayer = i == 0 ? address(largeParty[localSlot].data())
                                            : i == 4 && localSlot == 4
                                                ? address(largeParty[5].data())
                                                : 0;
                require(field<Address>(hud.data(), i * partSize) == expectedPlayer,
                        "Personal HUD retained another seat or lost its controlled twin");
            }
            require(field<Address>(game.data(), playersOffset) == address(roster.data()),
                    "Personal HUD changed the gameplay roster");
        }
        localSlot = 1;
        connectedMask &= ~(1u << 2);
        expectPersonalHud = false;
        roster.erase(roster.begin() + 2);
        setRoster();
        callHud(7);
        require(field<Address>(hud.data(), partSize) == address(largeParty[1].data()) &&
                    field<Address>(hud.data(), 3 * partSize) == address(largeParty[4].data()),
                "A sparse four-seat team did not regain its team HUD");

        std::array<unsigned char, 0x300> stats{};
        using Query = int(__attribute__((thiscall))*)(void*, void*);
        const auto statQuery = reinterpret_cast<Query>(image + entries[0]);
        field<Address>(stats.data(), 0x114 + 0xcc) = address(players[0].data());
        require(statQuery(stats.data(), players[1].data()) == 1 && statResets == 1 &&
                    statQueries == 1,
                "Stat HUD did not reset a stale teammate cache");
        require(statQuery(stats.data(), players[1].data()) == 1 && statResets == 1 &&
                    statQueries == 2,
                "Repeated local stat query discarded its cache");
        require(statQuery(stats.data(), players[0].data()) == -1 && statQueries == 2,
                "Remote actor reached local stat HUD");
        require(statQuery(stats.data(), nullptr) == -1 && statQueries == 2,
                "Missing stat actor was dereferenced");
        const auto historyQuery = reinterpret_cast<Query>(image + entries[2]);
        require(historyQuery(hud.data() + historyOffset, players[1].data()) == 7 &&
                    historyQueries == 1 && !depth && !localDepth,
                "History HUD did not restore the local-only view");
        require(historyQuery(hud.data() + historyOffset, players[0].data()) == -1 &&
                    historyQueries == 1,
                "Remote actor reached local history HUD");
        localSlot = -1;
        require(historyQuery(hud.data() + historyOffset, players[0].data()) == 7 &&
                    historyQueries == 2,
                "Offline history no longer follows native behavior");
        const auto resetAbi = native_fixture::call(image + entries[1], stats.data(), {});
        require(resetAbi.balanced && resetAbi.preserved, "Stat reset violated thiscall ABI");
        const auto playerAbi = native_fixture::call(image + entries[4], hud.data(), {});
        require(playerAbi.balanced && playerAbi.preserved, "PlayerHUD reset violated thiscall ABI");
        isaac::rooms::withView([&] {
            const auto historyAbi =
                native_fixture::call(image + entries[3], hud.data() + historyOffset, {1});
            require(historyAbi.balanced && historyAbi.preserved,
                    "History recompute violated thiscall ABI");
        });
        field<Address>(image, gameGlobal) = 0;
        localSlot = 1;
        const auto noGame = hud;
        callHud(6);
        require(hud == noGame && !depth, "Released Game changed native HUD bindings");
        for (auto index : {0u, 2u, 5u, 6u, 7u})
            require(MH_RemoveHook(image + entries[index]) == MH_OK,
                    "Remove frontend HUD fixture hook");
        require(MH_Uninitialize() == MH_OK, "Uninitialize frontend HUD fixture");
        VirtualFree(image, 0, MEM_RELEASE);
        std::cout
            << "Frontend HUD native ownership, local views, lifecycle and hook rollback passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

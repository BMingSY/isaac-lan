#include "engine/versions/j460/cursed_mist.h"
#include "test_support.h"
#include <algorithm>
#include <array>
#include <map>
#include <vector>

using namespace isaac::engine::j460::cursed_mist;
namespace entry = isaac::engine::j460::entry;
constexpr int familiarType = 3, abyssLocust = 231, wisp = 88;
constexpr Address host = 1, guest = 2, subplayer = 3;
struct Familiar {
    Address owner;
    int variant, subtype, state;
};
struct Escape {
    FamiliarQueries queries;
    std::map<Address, Familiar> living;
    std::map<Address, std::vector<Familiar>> saved;
    std::map<Address, bool> suppressed;
    Address next = 100;

    void spawn(Address owner, int variant, int subtype, int state) {
        living.emplace(next++, Familiar{owner, variant, subtype, state});
    }
    std::vector<Address> find(Address caller, int variant = -1, bool borrowed = true) {
        std::vector<Address> matches;
        for (const auto& [id, familiar] : living)
            if (variant == -1 || familiar.variant == variant)
                matches.push_back(id);
        QueryResult result{borrowed, matches.data(), static_cast<unsigned>(matches.size()),
                           static_cast<unsigned>(matches.size())};
        queries.filter(result, caller, familiarType, variant, -1, false, false,
                       [&](Address entity) { return living.at(entity).owner; });
        require(result.borrowed == borrowed && result.data == matches.data() &&
                    result.capacity == matches.size(),
                "Query filtering changed native buffer ownership or allocation");
        matches.resize(result.count);
        return matches;
    }
    void enter(Address owner) {
        queries.withOwner(owner, [&] {
            if (suppressed[owner])
                return;
            suppressed[owner] = true;
            saved[owner].clear();
            // Native suppression saves the query results, then removes locusts.
            for (const auto id : find(entry::playerMistStoreQueryReturn)) {
                saved[owner].push_back(living.at(id));
                living.erase(id);
            }
        });
    }
    void leave(Address owner) {
        queries.withOwner(owner, [&] {
            if (!suppressed[owner])
                return;
            suppressed[owner] = false;
            std::map<int, unsigned> restored;
            for (const auto& state : saved[owner]) {
                // Native restore spawns for this player, then selects the nth
                // result of the variant query to restore its saved payload.
                spawn(owner, state.variant, state.subtype, 0);
                auto found = find(entry::playerMistRestoreQueryReturn, state.variant, false);
                living.at(found.at(restored[state.variant]++)).state = state.state;
            }
            saved[owner].clear();
        });
    }
};
int main() {
    Escape room;
    room.spawn(host, abyssLocust, 0, 11);
    room.spawn(guest, abyssLocust, 118, 22);
    room.spawn(host, abyssLocust, 118, 33);
    room.enter(guest);
    require(room.living.size() == 2 && room.saved[guest].size() == 1 &&
                room.saved[guest][0].owner == guest,
            "Entering teammate captured another player's locusts");
    room.enter(host);
    require(room.living.empty() && room.saved[host].size() == 2,
            "Second entrant did not preserve their own locusts");
    for (unsigned doorway = 0; doorway < 8; ++doorway) {
        room.enter(host);
        room.enter(guest);
    }
    room.leave(host);
    room.leave(guest);
    require(room.living.size() == 3, "Escape return lost or duplicated locusts");
    for (const auto& [id, familiar] : room.living) {
        (void)id;
        require((familiar.owner == guest && familiar.subtype == 118 && familiar.state == 22) ||
                    (familiar.owner == host && familiar.subtype == 0 && familiar.state == 11) ||
                    (familiar.owner == host && familiar.subtype == 118 && familiar.state == 33),
                "Return restored a locust's payload to the wrong owner or subtype");
    }
    room.leave(host);
    room.leave(guest);
    require(room.living.size() == 3 && room.saved[host].empty() && room.saved[guest].empty(),
            "Repeated return reused a consumed backup");
    // One player remains in the ordinary room throughout another escape.
    room.enter(host);
    require(room.living.size() == 1 && room.living.begin()->second.owner == guest,
            "Resident teammate lost their familiar during a split-room escape");
    room.leave(host);
    require(room.living.size() == 3, "Later escape could not restore a fresh backup");

    room.spawn(subplayer, wisp, 0, 44);
    room.queries.withOwner(host, [&] {
        room.queries.withOwner(subplayer, [&] {
            const auto child = room.find(entry::playerMistStoreQueryReturn);
            require(child.size() == 1 && room.living.at(child.front()).owner == subplayer,
                    "Nested subplayer suppression borrowed the outer owner's familiars");
        });
        require(room.find(entry::playerMistStoreQueryReturn).size() == 2,
                "Nested suppression did not restore the parent owner");
        require(room.find(entry::playerMistStoreQueryReturn + 1).size() == 4,
                "An unrelated native query was filtered");
        room.queries.withOwner(0, [&] {
            require(room.find(entry::playerMistStoreQueryReturn).size() == 4,
                    "Solo/replica passthrough retained an outer owner");
        });
    });
    try {
        room.queries.withOwner(host, [] { throw std::runtime_error("failed native entry"); });
    } catch (const std::runtime_error&) {
    }
    require(room.find(entry::playerMistStoreQueryReturn).size() == 4,
            "Failed entry leaked the owner into later room or floor queries");

    std::array<Address, 3> candidates{100, 101, 102};
    room.queries.withOwner(host, [&] {
        for (bool borrowed : {false, true}) {
            QueryResult result{borrowed, candidates.data(), 3, 3};
            room.queries.filter(result, entry::playerMistStoreQueryReturn, familiarType, -1, -1,
                                false, false, [](Address) { return guest; });
            require(result.count == 0 && result.borrowed == borrowed && result.capacity == 3,
                    "Empty owned result retained someone else's familiars");
        }
        for (const auto [type, variant, subtype, cache, friendly] :
             {std::array<int, 5>{5, -1, -1, 0, 0},
              {3, 206, -1, 0, 0},
              {3, 231, 118, 0, 0},
              {3, -1, -1, 1, 0},
              {3, -1, -1, 0, 1}}) {
            QueryResult result{true, candidates.data(), 3, 3};
            room.queries.filter(result, entry::playerMistRestoreQueryReturn, type, variant, subtype,
                                cache, friendly, [](Address) { return guest; });
            require(result.count == 3, "An unsupported native query contract was changed");
        }
        QueryResult malformed{true, nullptr, 0, 1};
        room.queries.filter(malformed, entry::playerMistStoreQueryReturn, familiarType, -1, -1,
                            false, false,
                            [](Address) -> Address { throw std::runtime_error("invalid read"); });
        require(malformed.count == 1, "Malformed descriptor was partially overwritten");
    });
}

#pragma once
#include "compat/routes/mines.h"
#include "engine/versions/j460/entrypoints.h"
#include <cstdint>
#include <utility>

namespace isaac::engine::j460::cursed_mist {
using Address = std::uintptr_t;
// EntityList::FindByType's native result descriptor. Only the result's pointer
// sequence and count may be changed; allocation and borrowed status stay native.
struct QueryResult {
    bool borrowed;
    Address* data;
    unsigned capacity, count;
};
class FamiliarQueries {
  public:
    template <class Action> void withOwner(Address owner, Action&& action) {
        struct Restore {
            Address& current;
            Address previous;
            ~Restore() {
                current = previous;
            }
        } restore{owner_, std::exchange(owner_, owner)};
        std::forward<Action>(action)();
    }

    template <class Owner>
    void filter(QueryResult& result, Address caller, int type, int variant, int subtype, bool cache,
                bool ignoreFriendly, Owner&& owner) const {
        if (!owner_ || cache || ignoreFriendly ||
            (caller != entry::playerMistStoreQueryReturn &&
             caller != entry::playerMistRestoreQueryReturn) ||
            !compat::routes::mistFamiliarQuery(type, variant, subtype))
            return;
        // These two native queries return detached result buffers, never the
        // room's entity lists. Bound the descriptor before reading its entries.
        constexpr unsigned maxResults = 65536;
        if (result.count > result.capacity || result.count > maxResults ||
            (result.count && !result.data))
            return;
        unsigned kept = 0;
        for (unsigned i = 0; i < result.count; ++i)
            if (result.data[i] && owner(result.data[i]) == owner_)
                result.data[kept++] = result.data[i];
        result.count = kept;
    }

  private:
    Address owner_ = 0;
};
bool install(Address image);
} // namespace isaac::engine::j460::cursed_mist

#pragma once
#include "core/party.h"
#include <cstdint>
#include <cstring>
#include <unordered_map>

namespace isaac::engine::player_seats {
inline constexpr int nativeGamepads = 4;
inline int device(int owner) {
    return owner > 0 && owner <= static_cast<int>(party::maxPlayers)
               ? (owner - 1) % nativeGamepads + 1
               : 0;
}
// PlayerManager owns the actors. Only additional LAN owners need an entry.
// Check the creation seed when a live actor reuses an old allocation.
struct Association {
    int owner;
    unsigned seedOffset;
    std::uint32_t seed;
};
inline std::unordered_map<std::uintptr_t, Association> additional;
inline std::uint32_t seed(std::uintptr_t player, unsigned offset) {
    std::uint32_t value;
    std::memcpy(&value, reinterpret_cast<const void*>(player + offset), sizeof(value));
    return value;
}
inline void bind(std::uintptr_t player, int owner, unsigned offset) {
    if (owner > nativeGamepads)
        additional.insert_or_assign(player, Association{owner, offset, seed(player, offset)});
    else
        additional.erase(player);
}
inline void inherit(std::uintptr_t player, std::uintptr_t source) {
    if (const auto entry = additional.find(source); entry != additional.end())
        bind(player, entry->second.owner, entry->second.seedOffset);
}
inline int owner(std::uintptr_t player, int physical) {
    if (additional.empty())
        return physical;
    const auto found = additional.find(player);
    if (found != additional.end() && device(found->second.owner) == physical &&
        found->second.seed == seed(player, found->second.seedOffset))
        return found->second.owner;
    return physical;
}
} // namespace isaac::engine::player_seats

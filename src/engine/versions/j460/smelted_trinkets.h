#pragma once
#include "engine/versions/j460/layout.h"
#include <cstdint>
#include <span>
#include <stdexcept>
#include <vector>

namespace isaac::engine::j460::smelted_trinkets {
using Address = std::uintptr_t;
static_assert(sizeof(Address) == 4);
struct Counts {
    std::int16_t normal = 0, golden = 0;
    bool operator==(const Counts&) const = default;
};
static_assert(sizeof(Counts) == 4);
struct Entry {
    std::uint16_t id;
    Counts counts;
    bool operator==(const Entry&) const = default;
};
using State = std::vector<Entry>;
inline constexpr unsigned maxTypes = 0x8000;
inline std::span<Counts> slots(Address player) {
    const auto vector = reinterpret_cast<const Address*>(player + layout::player::smeltedTrinkets);
    const auto first = vector[0], last = vector[1], capacity = vector[2];
    if ((!first && (last || capacity)) || last < first || capacity < last ||
        (last - first) % sizeof(Counts) || (capacity - first) % sizeof(Counts) ||
        (capacity - first) / sizeof(Counts) > maxTypes)
        throw std::runtime_error("Invalid smelted trinket vector");
    return {reinterpret_cast<Counts*>(first), (last - first) / sizeof(Counts)};
}
inline State capture(Address player) {
    const auto values = slots(player);
    State result;
    for (unsigned id = 1; id < values.size(); ++id) {
        const auto counts = values[id];
        if (counts.normal < 0 || counts.golden < 0)
            throw std::runtime_error("Invalid smelted trinket count");
        if (counts.normal || counts.golden)
            result.push_back({static_cast<std::uint16_t>(id), counts});
    }
    return result;
}
inline bool restore(Address player, const State& desired) {
    const auto values = slots(player);
    unsigned previous = 0;
    for (const auto& entry : desired) {
        if (entry.id <= previous || entry.id >= values.size() || entry.counts.normal < 0 ||
            entry.counts.golden < 0 || (!entry.counts.normal && !entry.counts.golden))
            throw std::runtime_error("Invalid smelted trinket state");
        previous = entry.id;
    }
    // The game owns this config-sized vector. Reconcile its counters in place;
    // do not replay item use, allocate history entries or change held trinkets.
    auto next = desired.begin();
    bool changed = false;
    for (unsigned id = 1; id < values.size(); ++id) {
        const auto wanted = next != desired.end() && next->id == id ? (next++)->counts : Counts{};
        if (values[id] != wanted) {
            values[id] = wanted;
            changed = true;
        }
    }
    return changed;
}
} // namespace isaac::engine::j460::smelted_trinkets

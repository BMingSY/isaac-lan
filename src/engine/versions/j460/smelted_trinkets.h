#pragma once
#include "engine/versions/common/smelted_trinkets.h"
#include "engine/versions/j460/layout.h"
namespace isaac::engine::j460::smelted_trinkets {
using native_smelted_trinkets::Address;
using native_smelted_trinkets::Counts;
using native_smelted_trinkets::Entry;
using native_smelted_trinkets::State;
inline constexpr native_smelted_trinkets::Layout fields{layout::player::smeltedTrinkets};
inline State capture(Address player) {
    return native_smelted_trinkets::capture(fields, player);
}
inline bool restore(Address player, const State& state) {
    return native_smelted_trinkets::restore(fields, player, state);
}
} // namespace isaac::engine::j460::smelted_trinkets

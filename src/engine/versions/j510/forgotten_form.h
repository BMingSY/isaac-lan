#pragma once
#include "engine/versions/common/forgotten_form.h"
#include "engine/versions/j510/layout.h"

namespace isaac::engine::j510::forgotten_form {
using native_forgotten_form::Swap;
inline constexpr native_forgotten_form::Layout fields{
    layout::player::type, layout::player::coopGhost, layout::player::subplayer,
    layout::entity::type};
inline bool restore(std::uintptr_t player, int desired, Swap swap) {
    return native_forgotten_form::restore(fields, player, desired, swap);
}
} // namespace isaac::engine::j510::forgotten_form

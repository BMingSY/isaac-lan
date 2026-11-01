#pragma once
#include "compat/game_ids.h"
#include <cstdint>

namespace isaac::compat::items {
inline bool validActiveData(int item, std::int32_t data) {
    // D Infinity stores the selected die in the high word; native HUD/use
    // indexes its ten-entry die table directly. The low word is charge data.
    return item != ids::collectible::dInfinity || (static_cast<std::uint32_t>(data) >> 16) < 10;
}
} // namespace isaac::compat::items

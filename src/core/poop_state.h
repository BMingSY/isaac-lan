#pragma once
#include "net/protocol.h"
#include <algorithm>
#include <array>
#include <limits>

namespace isaac::actors {
struct PoopState {
    unsigned mana;
    std::array<std::uint8_t, 6> queue;
};
inline PoopState readPoopState(lan::Reader& input) {
    PoopState value{input.u32(), {}};
    for (auto& spell : value.queue)
        spell = input.u8();
    input.finish();
    if (value.mana > static_cast<unsigned>(std::numeric_limits<int>::max()) ||
        std::any_of(value.queue.begin(), value.queue.end(), [](auto spell) { return spell > 11; }))
        throw std::runtime_error("Invalid Tainted Blue Baby consumables");
    return value;
}
} // namespace isaac::actors

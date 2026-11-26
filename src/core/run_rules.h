#pragma once
#include <cstdint>
namespace isaac {
// Only the common marker travels on the wire. Lua assigns its own local slots above this boundary.
inline constexpr unsigned externalRuleBase = 0x8000, maxLobbyRules = 64;
// Opaque run identity plus generic lobby constraints. Gameplay interprets the ID.
struct RunRules {
    std::uint16_t id = 0, version = 0, character = 65535;
    std::uint8_t difficulty = 255;
    bool transient = false;
    std::uint64_t options = 0;
    std::uint64_t contract = 0;
    bool operator==(const RunRules&) const = default;
    bool valid() const {
        if (id > externalRuleBase || (id == externalRuleBase) != (contract != 0) ||
            (contract && !transient))
            return false;
        return id ? version != 0 && (difficulty <= 3 || difficulty == 255)
                  : version == 0 && character == 65535 && difficulty == 255 && !transient;
    }
};
} // namespace isaac

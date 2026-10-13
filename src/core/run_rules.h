#pragma once
#include <cstdint>
namespace isaac {
// Opaque run identity plus generic lobby constraints. Gameplay interprets the ID.
struct RunRules {
    std::uint16_t id = 0, version = 0, character = 65535;
    std::uint8_t difficulty = 255;
    bool transient = false;
    bool operator==(const RunRules&) const = default;
    bool valid() const {
        return id ? version != 0 && (difficulty <= 3 || difficulty == 255) : *this == RunRules{};
    }
};
} // namespace isaac

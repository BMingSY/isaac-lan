#pragma once
#include <array>
#include <cstdint>
#include <span>
#include <vector>

namespace isaac::compat::characters {
struct CharacterUnlock {
    std::uint16_t type;
    int achievement;
};

// Native character-menu order; alternate forms are not starting characters.
// Achievement IDs match the J460 PlayerConfig unlock field. Both Eden forms
// additionally require the same Eden-token counter when starting a new run.
inline constexpr std::array<CharacterUnlock, 34> characterUnlocks{{
    {0, -1},   {1, 1},    {2, 2},    {3, 3},    {4, 32},   {5, 42},   {6, 67},
    {7, 79},   {8, 80},   {9, 81},   {10, 82},  {13, 199}, {14, 251}, {15, 340},
    {16, 390}, {18, 404}, {19, 405}, {21, 474}, {22, 475}, {23, 476}, {24, 477},
    {25, 478}, {26, 479}, {27, 480}, {28, 481}, {29, 482}, {30, 483}, {31, 484},
    {32, 485}, {33, 486}, {34, 487}, {35, 488}, {36, 489}, {37, 490},
}};
inline constexpr unsigned edenTokensCounter = 21;

inline bool characterUnlocked(std::uint16_t type, std::span<const std::uint8_t> achievements) {
    for (const auto& entry : characterUnlocks) {
        if (entry.type == type)
            return entry.achievement < 0 ||
                   (static_cast<unsigned>(entry.achievement) < achievements.size() &&
                    achievements[entry.achievement] != 0);
    }
    return false;
}

inline bool characterAvailable(std::uint16_t type, std::span<const std::uint8_t> achievements,
                               std::uint32_t edenTokens) {
    return characterUnlocked(type, achievements) && ((type != 9 && type != 30) || edenTokens != 0);
}

inline std::vector<std::uint16_t> availableCharacters(std::span<const std::uint8_t> achievements,
                                                      std::uint32_t edenTokens) {
    std::vector<std::uint16_t> result;
    result.reserve(characterUnlocks.size());
    for (const auto& entry : characterUnlocks)
        if (characterAvailable(entry.type, achievements, edenTokens))
            result.push_back(entry.type);
    return result;
}
} // namespace isaac::compat::characters

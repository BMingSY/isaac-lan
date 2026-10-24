#pragma once
#include "net/protocol.h"
#include <cstdint>
#include <string>
#include <vector>
#include <optional>

namespace isaac::characters {
struct Entry {
    std::uint16_t type;
    std::string name, animation, portraitPath, portraitAnm2Path;
    bool tainted = false, selectable = false, unlocked = false;
};
struct Catalogue {
    bool ready = false;
    std::vector<Entry> entries;
};
// Copy the game's character-menu catalogue. Eligibility uses this peer's own
// progress in a synchronous frontend context, restoring native state on return.
Catalogue catalogue(std::uintptr_t image, const lan::Progress& personal);
// Packed read-only character-card presentation. Zero means unavailable.
std::uint32_t completionPreview(unsigned character, const lan::Progress& personal);
std::optional<std::array<std::uint8_t, 12>> completionLayers(std::uint32_t preview);
} // namespace isaac::characters

#pragma once

namespace isaac::compat::bosses {
inline bool gatherHomeCombat(int stage, int kind, bool dogma, unsigned audience,
                             unsigned connected) {
    return stage == 13 && kind == 1 && dogma && (audience & connected) != connected;
}
inline bool finalCombat(int stage, int kind, unsigned entityType, unsigned variant = 0) {
    if (stage == 11 && (kind == 0 || kind == 1))
        return entityType == 102 || entityType == 273 || entityType == 274 || entityType == 275;
    if (stage == 12)
        return entityType == 412;
    if (stage == 9 && kind == 0)
        return entityType == 406 || entityType == 407;
    if (stage == 8 && (kind == 4 || kind == 5))
        return entityType == 912;
    return stage == 13 && kind == 1 &&
           (entityType == 950 || entityType == 951 || (entityType == 960 && variant == 4));
}
} // namespace isaac::compat::bosses

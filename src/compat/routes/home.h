#pragma once

namespace isaac::compat::routes {
// The native hourglass room call can select this floor transition instead.
inline bool homeTransition(bool same, int animation) {
    return !same && animation == 6;
}
// A first-room Home use needs no saved hourglass checkpoint. Restrict that
// exception to the native route's inputs; the game still selects the route.
inline bool hourglassHomeSource(int stage, int stageType, int difficulty, int roomIndex,
                                int startIndex, bool firstVisit) {
    return stage == 1 && stageType != 4 && stageType != 5 && difficulty != 2 && difficulty != 3 &&
           roomIndex == startIndex && firstVisit;
}
} // namespace isaac::compat::routes

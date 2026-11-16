#pragma once

namespace isaac::compat::enemies {
inline bool capturedRoomReturn(int destination, int startRoom, int direction, int animation,
                               int dimension) {
    constexpr int fade = 1;
    return startRoom >= 0 && startRoom < 169 && destination == startRoom && direction == -1 &&
           animation == fade && dimension == -1;
}
} // namespace isaac::compat::enemies

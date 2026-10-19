#pragma once
#include <algorithm>

namespace isaac::rooms {
// Native room age is gameFrame - enteredFrame. A paused room must not age
// while other occupied rooms keep advancing the shared game frame.
class RoomClock {
    int previous = 0;

  public:
    void reset(int frame) {
        previous = frame;
    }
    void advance(int frame, bool paused, int& enteredFrame) {
        const int elapsed = std::max(0, frame - previous);
        previous = frame;
        if (paused)
            enteredFrame += elapsed;
    }
};
} // namespace isaac::rooms

#pragma once
#include <optional>

namespace isaac::engine::j460 {
// SetNextStage reads the departure room long after StartStageTransition.
// Retain only its scalar index; never retain or activate an old Room object.
class FloorSource {
    std::optional<int> source;

  public:
    bool begin(int index) {
        if (index < -20 || index >= 169)
            return false;
        source = index;
        return true;
    }
    void reset() {
        source.reset();
    }
    int room(int current) const {
        return source.value_or(current);
    }
    template <class Select> void select(int& currentRoom, Select&& next) const {
        if (!source) {
            next();
            return;
        }
        struct Restore {
            int& field;
            int value;
            ~Restore() {
                field = value;
            }
        } restore{currentRoom, currentRoom};
        currentRoom = *source;
        next();
    }
};
} // namespace isaac::engine::j460

#pragma once
#include <array>
#include <cstdint>
#include <map>
#include <optional>

namespace isaac::presentation {
class IntroBarrier {
  public:
    using Room = std::array<int, 4>;
    void start(Room room, unsigned serial, unsigned tick, unsigned audience) {
        if (audience)
            waiting[room] = {serial, tick, audience};
    }
    std::optional<Room> observe(unsigned slot, unsigned serial, bool active) {
        if (slot >= 4 || active)
            return std::nullopt;
        for (auto& [room, value] : waiting) {
            if (value.serial == serial && (value.audience & (1u << slot))) {
                value.audience &= ~(1u << slot);
                return room;
            }
        }
        return std::nullopt;
    }
    bool paused(Room room, unsigned tick, unsigned connected) {
        const auto entry = waiting.find(room);
        if (entry == waiting.end())
            return false;
        entry->second.audience &= connected;
        if (!entry->second.audience || tick - entry->second.tick > 600) {
            waiting.erase(entry);
            return false;
        }
        return true;
    }
    void clear() {
        waiting.clear();
    }

  private:
    struct Wait {
        unsigned serial, tick, audience;
    };
    std::map<Room, Wait> waiting;
};
} // namespace isaac::presentation

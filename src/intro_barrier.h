#pragma once
#include <array>
#include <cstdint>
#include <map>

namespace isaac::presentation {
class IntroBarrier {
  public:
    using Room = std::array<int, 4>;
    void start(Room room, unsigned serial, unsigned tick, unsigned audience) {
        if (const auto guests = audience & ~1u)
            waiting[room] = {serial, tick, guests};
    }
    void observe(unsigned slot, unsigned serial, bool active) {
        if (slot >= 4 || active)
            return;
        for (auto& [room, value] : waiting) {
            (void)room;
            if (value.serial == serial)
                value.audience &= ~(1u << slot);
        }
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

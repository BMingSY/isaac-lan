#pragma once
#include <array>
#include <cstdint>
#include <map>
#include <optional>

namespace isaac::presentation {
class IntroBarrier {
  public:
    using Room = std::array<int, 4>;
    static constexpr unsigned timeoutTicks = 600;
    void start(Room room, unsigned serial, unsigned tick, unsigned audience) {
        if (audience)
            waiting[room] = {serial, tick, audience, audience, audience, 0};
    }
    unsigned join(Room room, unsigned serial, unsigned tick, unsigned audience) {
        const auto entry = waiting.find(room);
        if (entry == waiting.end())
            return 0;
        auto& value = entry->second;
        if (value.serial != serial || !value.blocking || tick - value.tick > timeoutTicks)
            return 0;
        const auto added = audience & ~value.enrolled;
        value.enrolled |= added;
        value.audience |= added;
        return added;
    }
    std::optional<Room> observe(unsigned slot, unsigned serial, bool active) {
        if (slot >= 4)
            return std::nullopt;
        for (auto& [room, value] : waiting) {
            if (value.serial == serial && (value.audience & (1u << slot))) {
                value.observed |= 1u << slot;
                if (active)
                    return std::nullopt;
                value.audience &= ~(1u << slot);
                value.blocking &= ~(1u << slot);
                return room;
            }
        }
        return std::nullopt;
    }
    void finish(unsigned serial) {
        for (auto& [room, value] : waiting)
            if (value.serial == serial)
                value.blocking = 0;
    }
    bool pending(unsigned slot, unsigned serial, unsigned tick) const {
        if (slot >= 4)
            return false;
        for (const auto& [room, value] : waiting)
            if (value.serial == serial && (value.audience & (1u << slot)) &&
                (value.blocking || !(value.observed & (1u << slot))) &&
                tick - value.tick <= timeoutTicks)
                return true;
        return false;
    }
    unsigned audience(unsigned serial, unsigned tick, unsigned connected) const {
        for (const auto& [room, value] : waiting)
            if (value.serial == serial && value.blocking && tick - value.tick <= timeoutTicks)
                return value.audience & connected;
        return 0;
    }
    bool paused(Room room, unsigned tick, unsigned connected) {
        const auto entry = waiting.find(room);
        if (entry == waiting.end())
            return false;
        entry->second.audience &= connected;
        entry->second.blocking &= connected;
        if (!entry->second.audience || tick - entry->second.tick > timeoutTicks) {
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
        // Original viewers set the duration. Every enrolled viewer must receive the
        // event and dismiss their own screen before this room resumes combat.
        unsigned serial, tick, audience, enrolled, blocking, observed;
    };
    std::map<Room, Wait> waiting;
};
} // namespace isaac::presentation

#pragma once
#include <chrono>
#include <cstddef>
#include <algorithm>

namespace isaac::lan {
// A stale, barely transmitted view may yield once to fresh state. Its replacement
// must finish, even when the producer continuously publishes oversized views.
class WorldEmission {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr auto staleAfter = std::chrono::milliseconds(250);
    static constexpr double finishSoonSeconds = 0.1;

  private:
    Clock::time_point started{};
    std::size_t total = 0, remaining = 0;
    bool protectedReplacement = false;

  public:
    void begin(std::size_t bytes, Clock::time_point now) {
        total = remaining = bytes;
        started = now;
    }
    void sent(std::size_t bytes) {
        remaining -= std::min(bytes, remaining);
        if (!remaining)
            protectedReplacement = false;
    }
    bool refreshDue(double bytesPerSecond, Clock::time_point now) const {
        return !protectedReplacement && remaining && now - started >= staleAfter &&
               remaining > total / 2 &&
               remaining / std::max(1.0, bytesPerSecond) > finishSoonSeconds;
    }
    bool replace(bool newer, double bytesPerSecond, Clock::time_point now) {
        if (!newer || !refreshDue(bytesPerSecond, now))
            return false;
        protectedReplacement = true;
        return true;
    }
};
} // namespace isaac::lan

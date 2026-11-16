#pragma once
#include "net/world_shards.h"
#include <chrono>

namespace isaac::lan {
// Receiver evidence, not application ACK gaps: a slow game thread may skip
// intact views. Reduce parity only after sustained clean shard delivery.
class WorldRedundancy {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr auto feedbackExpiry = std::chrono::seconds(2);
    static constexpr auto cleanInterval = std::chrono::seconds(3);
    static constexpr std::uint32_t cleanViews = 90;

  private:
    WorldShards::Quality previous;
    std::optional<Clock::time_point> received;
    Clock::time_point cleanAt{};
    std::uint32_t clean = 0;

  public:
    void penalize(Clock::time_point now) {
        clean = 0;
        cleanAt = now;
    }
    void observe(WorldShards::Quality value, Clock::time_point now) {
        if (value.repaired > value.completed)
            throw std::runtime_error("Invalid shard quality");
        if (value.completed < previous.completed || value.repaired < previous.repaired ||
            value.discarded < previous.discarded)
            return; // Reordered cumulative feedback.
        if (!received || now - *received >= feedbackExpiry || value.repaired != previous.repaired ||
            value.discarded != previous.discarded)
            penalize(now);
        else
            clean += value.completed - previous.completed;
        previous = value;
        received = now;
    }
    std::size_t parity(Clock::time_point now) const {
        return received && now - *received < feedbackExpiry && clean >= cleanViews &&
                       now - cleanAt >= cleanInterval
                   ? 1
                   : WorldShards::parityShards;
    }
};
} // namespace isaac::lan

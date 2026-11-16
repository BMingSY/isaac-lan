#pragma once
#include <algorithm>
#include <chrono>
#include <deque>

namespace isaac::lan {
// A recent path baseline, independent of game-thread/application receipts.
// Sampling buckets bound memory even when many ACKs arrive in one service call.
class PathLatency {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr auto lifetime = std::chrono::seconds(2);
    static constexpr auto interval = std::chrono::milliseconds(50);

  private:
    struct Sample {
        Clock::time_point at;
        int milliseconds;
    };
    std::deque<Sample> samples;

  public:
    int observe(int milliseconds, Clock::time_point now) {
        while (!samples.empty() && now - samples.front().at >= lifetime)
            samples.pop_front();
        if (milliseconds >= 0) {
            if (!samples.empty() && now - samples.back().at < interval)
                samples.back().milliseconds = std::min(samples.back().milliseconds, milliseconds);
            else
                samples.push_back({now, milliseconds});
        }
        int result = -1;
        for (const auto& sample : samples)
            result = result < 0 ? sample.milliseconds : std::min(result, sample.milliseconds);
        return result;
    }
};
} // namespace isaac::lan

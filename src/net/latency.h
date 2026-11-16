#pragma once
#include "net/protocol.h"
#include <chrono>
#include <optional>

namespace isaac::lan {
// A relay preserves sample age: broadcasting an old value is not a measurement.
class LatencySample {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr auto lifetime = std::chrono::seconds(3);
    static constexpr auto reportInterval = std::chrono::milliseconds(500);
    static constexpr std::uint16_t unknown = 65535, maximum = unknown - 1;

  private:
    int milliseconds = -1;
    std::optional<Clock::time_point> measuredAt;

  public:
    void record(int value, Clock::time_point at = Clock::now()) {
        if (value < 0) {
            *this = {};
            return;
        }
        milliseconds = std::min<int>(value, maximum);
        measuredAt = at;
    }
    int value(Clock::time_point now = Clock::now()) const {
        return measuredAt && now - *measuredAt < lifetime ? milliseconds : -1;
    }
    void write(Writer& writer, Clock::time_point now = Clock::now()) const {
        const auto ms = value(now);
        writer.u16(ms < 0 ? unknown : ms);
        writer.u16(
            ms < 0
                ? 0
                : std::chrono::duration_cast<std::chrono::milliseconds>(now - *measuredAt).count());
    }
    static LatencySample read(Reader& reader, Clock::time_point now = Clock::now()) {
        const auto ms = reader.u16(), age = reader.u16();
        LatencySample result;
        if (ms != unknown)
            result.record(ms, now - std::chrono::milliseconds(age));
        return result;
    }
};
} // namespace isaac::lan

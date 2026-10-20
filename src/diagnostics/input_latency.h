#pragma once
#include <array>
#include <chrono>
#include <cstdint>
#include <optional>

namespace isaac::diagnostics {
// Local-clock intervals only. An acknowledgement measures receipt/application
// of a control sample, not proof that a particular weapon effect fired.
class InputLatency {
    using Clock = std::chrono::steady_clock;
    struct Sample {
        std::uint32_t sequence;
        Clock::time_point at;
        bool presented = false;
    };
    std::array<std::optional<Sample>, 128> samples;
    std::optional<std::uint32_t> acknowledged;

  public:
    void capture(std::uint32_t sequence, Clock::time_point at = Clock::now()) {
        samples[sequence % samples.size()] = Sample{sequence, at};
    }
    std::optional<double> present(std::uint32_t sequence, Clock::time_point at = Clock::now()) {
        auto& value = samples[sequence % samples.size()];
        if (!value || value->sequence != sequence || value->presented)
            return {};
        value->presented = true;
        return std::chrono::duration<double, std::milli>(at - value->at).count();
    }
    std::optional<double> confirm(std::uint32_t sequence, Clock::time_point at = Clock::now()) {
        if (acknowledged && sequence <= *acknowledged)
            return {};
        acknowledged = sequence;
        const auto& value = samples[sequence % samples.size()];
        if (!value || value->sequence != sequence)
            return {};
        return std::chrono::duration<double, std::milli>(at - value->at).count();
    }
};
} // namespace isaac::diagnostics

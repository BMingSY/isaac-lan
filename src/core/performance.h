#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace isaac::diagnostics {
struct Window {
    // Percentiles describe the latest 512 samples; count/mean/max describe
    // the whole interval. Memory does not grow during a long run.
    std::array<double, 512> samples{};
    std::uint64_t count = 0;
    double total = 0, maximum = 0;
    void add(double value) {
        if (!std::isfinite(value) || value < 0)
            return;
        samples[count % samples.size()] = value;
        ++count;
        total += value;
        maximum = std::max(maximum, value);
    }
    double percentile(unsigned percent) const {
        const auto size = static_cast<std::size_t>(std::min<std::uint64_t>(count, samples.size()));
        if (!size)
            return 0;
        auto ordered = samples;
        std::sort(ordered.begin(), ordered.begin() + size);
        const auto rank = std::max<std::size_t>(1, (size * std::min(percent, 100u) + 99) / 100);
        return ordered[rank - 1];
    }
};
} // namespace isaac::diagnostics

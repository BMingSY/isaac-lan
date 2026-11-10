#pragma once
#include "net/datagram_protocol.h"
#include "net/path_latency.h"
#include <algorithm>
#include <chrono>
#include <cstddef>
#include <optional>

namespace isaac::lan {
// Per-connection realtime byte budget. Control/input traffic does not wait for
// these tokens. All time is supplied by the caller so impaired links are testable.
class WorldPacing {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr double initialRate = 256 * 1024, minimumRate = 16 * 1024,
                            maximumRate = 8 * 1024 * 1024;
    static constexpr auto adjustmentInterval = std::chrono::milliseconds(200);
    static constexpr auto serviceInterval = std::chrono::milliseconds(5);
    static constexpr std::size_t minimumBurstDatagrams = 2, maximumBurstDatagrams = 16;
    static constexpr double queueAllowanceMs = 25;
    static constexpr auto congestionConfirmation = std::chrono::milliseconds(100);
    static constexpr unsigned minimumDelayedReceipts = 3;
    static constexpr double decreaseFactor = 0.75, increaseFactor = 1.25, minimumReceiptMs = 1;

  private:
    double rate = initialRate, credit = minimumBurstDatagrams * datagram::mtu;
    std::optional<Clock::time_point> updated, adjusted;
    bool received = false;
    PathLatency path;
    std::optional<Clock::time_point> delayedSince;
    unsigned delayedReceipts = 0;
    double burst() const {
        // One service interval of credit, with room for two small datagrams.
        // Idle time never earns a whole stale frame's worth of burst traffic.
        return std::clamp(rate * std::chrono::duration<double>(serviceInterval).count(),
                          double(minimumBurstDatagrams * datagram::mtu),
                          double(maximumBurstDatagrams * datagram::mtu));
    }
    void advance(Clock::time_point now) {
        if (updated)
            credit = std::min(
                burst(),
                credit +
                    std::max(0.0, std::chrono::duration<double>(now - *updated).count()) * rate);
        updated = now;
    }
    bool adjustable(Clock::time_point now) const {
        return !adjusted || now - *adjusted >= adjustmentInterval;
    }

  public:
    double bytesPerSecond() const {
        return rate;
    }
    bool ready(std::size_t bytes, Clock::time_point now) {
        advance(now);
        return credit >= static_cast<double>(bytes);
    }
    bool consume(std::size_t bytes, Clock::time_point now) {
        if (!ready(bytes, now))
            return false;
        credit -= bytes;
        return true;
    }
    void reserve(std::size_t bytes, Clock::time_point now) {
        // Reliable bootstrap/recovery must be deliverable even without a state
        // ACK, but its bytes also occupy the path before realtime can resume.
        advance(now);
        credit -= bytes;
    }
    void congested(Clock::time_point now) {
        if (!adjustable(now))
            return;
        advance(now);
        rate = std::max(minimumRate, rate * decreaseFactor);
        credit = std::min(credit, burst());
        adjusted = now;
    }
    void acknowledge(std::size_t bytes, double transitMs, int networkLatency,
                     Clock::time_point now) {
        advance(now);
        // ENet's RTT ends on the network thread. A busy renderer may defer the
        // application receipt; it limits the view window, not path capacity.
        if (networkLatency < 0)
            return;
        const auto baseline = path.observe(networkLatency, now);
        if (networkLatency > baseline + queueAllowanceMs) {
            if (!delayedSince)
                delayedSince = now;
            ++delayedReceipts;
            // Isolated jitter/loss recovery is not evidence of a full queue.
            // Require persistent delay across several application receipts.
            if (delayedReceipts >= minimumDelayedReceipts &&
                now - *delayedSince >= congestionConfirmation)
                congested(now);
            received = true;
            return;
        }
        delayedSince.reset();
        delayedReceipts = 0;
        if (!received) {
            // A large reliable bootstrap provides a conservative startup rate.
            // Small views cannot reveal capacity and keep the bounded default.
            rate =
                std::clamp(std::max(rate, bytes * 1000.0 / std::max(minimumReceiptMs, transitMs)),
                           minimumRate, maximumRate);
            adjusted = now;
        } else if (adjustable(now)) {
            rate = std::min(maximumRate, rate * increaseFactor);
            adjusted = now;
        }
        received = true;
    }
};
} // namespace isaac::lan

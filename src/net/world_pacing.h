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
    PathLatency path, deliveryPath;
    struct DeliveryWindow {
        std::uint64_t bytes, milliseconds;
        int minimumRtt;
    };
    std::optional<DeliveryWindow> deliveryWindow;
    int baseRtt = -1;
    std::size_t detailAllowance = 0;
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
    std::size_t optionalBudget() const {
        return detailAllowance;
    }
    void delivery(std::uint64_t bytes, std::uint64_t milliseconds, int rtt, Clock::time_point now) {
        constexpr auto routeHistory = std::chrono::seconds(30);
        constexpr std::uint64_t windowMs = 150;
        constexpr double utilization = 0.72, probeGain = 1.12, drainGain = 0.90;
        constexpr double detailSeconds = 0.008;
        if (deliveryWindow &&
            (bytes < deliveryWindow->bytes || milliseconds < deliveryWindow->milliseconds))
            return;
        baseRtt = deliveryPath.observe(rtt, now, routeHistory);
        if (!deliveryWindow) {
            deliveryWindow = DeliveryWindow{bytes, milliseconds, rtt};
            return;
        }
        auto& window = *deliveryWindow;
        window.minimumRtt = std::min(window.minimumRtt, rtt);
        const auto elapsed = milliseconds - window.milliseconds;
        if (elapsed < windowMs)
            return;
        const auto delivered = (bytes - window.bytes) * 1000.0 / elapsed;
        const bool queued = window.minimumRtt > baseRtt + queueAllowanceMs;
        const bool saturated = delivered >= utilization * rate;
        advance(now);
        if (queued)
            rate = std::clamp(std::min(rate, delivered * drainGain), minimumRate, maximumRate);
        else if (saturated)
            rate = std::clamp(std::max(rate, delivered) * probeGain, minimumRate, maximumRate);
        // Empty rooms cannot demonstrate link capacity. Probe optional drawing data
        // only in clear windows and leave room for the next gameplay publication.
        detailAllowance =
            queued || rtt > baseRtt + queueAllowanceMs
                ? 0
                : static_cast<std::size_t>(std::max(0.0, rate - delivered) * detailSeconds);
        credit = std::min(credit, burst());
        adjusted = now;
        window = {bytes, milliseconds, rtt};
    }
    std::size_t flightBudget(int fallbackRtt) const {
        const auto latency = baseRtt >= 0 ? baseRtt : fallbackRtt;
        const auto interval = (std::max(latency, 0) + queueAllowanceMs) / 1000.0;
        return std::max<std::size_t>(2 * datagram::mtu, static_cast<std::size_t>(rate * interval));
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

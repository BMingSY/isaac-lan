#pragma once
#include "net/socket.h"
#include <chrono>
#include <algorithm>
#include <memory>
namespace isaac::lan {
struct Peer : Socket {
    using Clock = std::chrono::steady_clock;
    struct CachedWorld {
        std::uint32_t tick;
        std::shared_ptr<const std::vector<std::uint8_t>> bytes;
        std::size_t wireBytes = 0;
        bool complete = false;
    };
    static constexpr std::size_t maxCachedBytes = 8 * maxWorldSize;
    static constexpr std::size_t maxInFlightBytes = 65536;
    static constexpr std::size_t maxInFlightStates = 16;
    bool accepted = false;
    std::string mods;
    bool loaded = false;
    bool waiting = false, ready = false, rejoining = false, hasInput = false;
    std::optional<Clock::time_point> loadingAt;
    std::shared_ptr<const Start> checkpoint;
    std::optional<Stage> floorAfterLoad;
    std::optional<Stage> sendingStage;
    std::size_t stageSent = 0;
    std::optional<WorldState> sending, pending;
    std::size_t worldSent = 0;
    std::uint32_t inputSequence = 0;
    std::optional<std::uint32_t> acknowledged;
    std::optional<CachedWorld> baseline;
    std::deque<CachedWorld> flight, decoded;
    bool sendingDelta = false;
    std::uint32_t sendingBase = 0;
    int minimumLatency = -1;
    std::size_t snapshotSent = 0;
    Clock::time_point packetAt = Clock::now();
    Clock::time_point connectedAt = Clock::now();
    Clock::time_point advancedAt = Clock::now(), inputAt = Clock::now();
    Clock::time_point pingAt = Clock::now() - std::chrono::seconds(1);
    std::uint32_t pingSequence = 0;
    bool pingPending = false;
    using Socket::Socket;
    void resetWorldCache() {
        baseline.reset();
        flight.clear();
        decoded.clear();
    }
    std::size_t cachedBytes() const {
        std::size_t bytes = baseline ? baseline->bytes->capacity() : 0;
        for (const auto& value : flight)
            bytes += value.bytes->capacity();
        for (const auto& value : decoded)
            bytes += value.bytes->capacity();
        return bytes;
    }
    std::size_t inFlightBytes() const {
        std::size_t bytes = 0;
        for (const auto& value : flight)
            bytes += value.wireBytes;
        return bytes;
    }
    std::size_t window() const {
        // Use the uncongested RTT, not queue-inflated ping, to size the window.
        return std::clamp<std::size_t>((std::max(0, minimumLatency) + 32) / 33 + 2, 4,
                                       maxInFlightStates);
    }
    void beginStage(const Stage& value) {
        sending.reset();
        pending.reset();
        resetWorldCache();
        sendingStage = value;
        stageSent = 0;
    }
};
} // namespace isaac::lan

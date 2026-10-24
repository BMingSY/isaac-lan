#pragma once
#include "net/socket.h"
#include "net/messages.h"
#include "net/world_transfer.h"
#include "net/checkpoint_transfer.h"
#include <chrono>
#include <algorithm>
#include <memory>
namespace isaac::lan {
struct Peer : Socket {
    using Clock = std::chrono::steady_clock;
    static constexpr auto maxCachedBytes = WorldTransfer::maxCachedBytes;
    static constexpr auto maxInFlightBytes = WorldTransfer::maxInFlightBytes;
    static constexpr auto maxInFlightStates = WorldTransfer::maxInFlightStates;
    bool accepted = false;
    std::string mods;
    bool loaded = false;
    bool waiting = false, ready = false, rejoining = false, hasInput = false;
    std::optional<Clock::time_point> loadingAt;
    std::shared_ptr<CheckpointPreparation> preparingCheckpoint;
    std::shared_ptr<const PreparedCheckpoint> checkpoint;
    bool checkpointQueued = false;
    std::optional<Stage> floorAfterLoad;
    std::shared_ptr<const Stage> sendingStage;
    std::optional<WorldState> pending;
    std::uint32_t inputSequence = 0;
    std::optional<std::uint32_t> edgeSequence;
    std::deque<InputSample> inputEdges;
    std::optional<std::uint32_t> acknowledged;
    int minimumLatency = -1;
    Clock::time_point packetAt = Clock::now();
    Clock::time_point connectedAt = Clock::now();
    Clock::time_point advancedAt = Clock::now(), inputAt = Clock::now();
    Clock::time_point pingAt = Clock::now() - std::chrono::seconds(1);
    std::uint32_t pingSequence = 0;
    bool pingPending = false;
    using Socket::Socket;
    void submitInput(InputSample sample) {
        if (sample.input.triggered) {
            auto event = inputMessage(sample);
            event.bytes[0] = static_cast<std::uint8_t>(Message::inputEdges);
            sendMessage(event);
        }
        sample.input.triggered = 0;
        sendMessage(inputMessage(sample));
    }
    void consumeEdges(InputFrame& input, const std::optional<InputRoom>& room) {
        if (Clock::now() - inputAt > std::chrono::milliseconds(500)) {
            inputEdges.clear();
            return;
        }
        // Bounded by samples, not simulated host ticks: 120 samples cover at
        // most two seconds at the default 60 Hz rate. Context also expires
        // actions at room/floor boundaries, including reordered delivery.
        constexpr std::uint32_t maxEdgeSampleAge = 120;
        while (!inputEdges.empty() && hasInput && inputEdges.front().sequence <= inputSequence) {
            const auto& event = inputEdges.front();
            std::uint16_t edges = 0;
            if (inputSequence - event.sequence <= maxEdgeSampleAge)
                edges = retainedInputEdges(event.input, event.room, room);
            inputEdges.pop_front();
            if (edges) {
                // Two separate presses delivered together are still two host
                // updates, rather than one bitwise-OR action.
                input.triggered |= edges;
                break;
            }
        }
    }
    void resetWorldCache(std::uint32_t epoch = 0) {
        pending.reset();
        if (pipe) {
            pipe->publication.take();
            auto generation = pipe->generation.load(std::memory_order_relaxed);
            ++generation.revision;
            generation.epoch = epoch;
            pipe->generation.store(generation, std::memory_order_release);
            io->signal();
        }
    }
    std::size_t cachedBytes() const {
        return pipe ? pipe->world.cached.load() : 0;
    }
    std::size_t inFlightBytes() const {
        return pipe ? pipe->world.flightBytes.load() : 0;
    }
    std::size_t window() const {
        return WorldTransfer::window(minimumLatency);
    }
    void beginStage(const Stage& value, bool reset = true) {
        if (reset)
            resetWorldCache(value.epoch);
        sendingStage = std::make_shared<const Stage>(value);
    }
};
} // namespace isaac::lan

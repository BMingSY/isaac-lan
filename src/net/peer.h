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
        sendMessage(inputMessage(sample));
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

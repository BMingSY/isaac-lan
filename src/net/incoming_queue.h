#pragma once
#include "core/latest_mailbox.h"
#include "core/spsc_queue.h"
#include "net/reliable_receiver.h"

namespace isaac::lan {
inline constexpr std::size_t maxIncomingBytes = 2 * maxWorldSize;
struct IncomingPacket {
    std::vector<std::uint8_t> bytes;
    std::optional<WorldState> world;
    std::optional<ReceivedBulk> bulk;
    std::size_t size() const {
        return bytes.size() + (world ? world->bytes.size() + world->stable.size() : 0) +
               (bulk ? bulk->size() : 0);
    }
};

// One network producer and one game-thread consumer. Realtime values are
// replaceable, but cannot overtake the reliable messages preceding them.
class IncomingQueue {
    enum Lane { worldLane, inputLane, receiptLane, laneCount };
    struct Latest {
        std::uint64_t barrier, generation;
        IncomingPacket packet;
    };
    SpscQueue<IncomingPacket, 128> ordered;
    std::array<LatestMailbox<Latest>, laneCount> latest;
    std::array<std::unique_ptr<Latest>, laneCount> deferred;
    std::atomic<std::uint64_t> generation{0};
    std::atomic<std::size_t> orderedBytes{0};
    std::uint64_t published = 0, consumed = 0;

  public:
    // Producer only. A floor/run boundary invalidates even a value that the
    // consumer already took from a mailbox while waiting for a reliable barrier.
    void invalidate() {
        generation.fetch_add(1, std::memory_order_release);
        for (auto& slot : latest)
            slot.take();
    }
    bool push(IncomingPacket packet) {
        if (!packet.size())
            return true;
        auto lane = laneCount;
        if (packet.world)
            lane = worldLane;
        else if (!packet.bytes.empty()) {
            const auto type = static_cast<Message>(packet.bytes.front());
            if (type == Message::input)
                lane = inputLane;
            else if (type == Message::applied)
                lane = receiptLane;
        }
        if (lane != laneCount) {
            latest[lane].publish(std::make_unique<Latest>(
                Latest{published, generation.load(std::memory_order_relaxed), std::move(packet)}));
            return true;
        }
        // Ordinary messages retain reserved space behind a completed large
        // archive. Additional archives remain bounded by the byte budget.
        if (ordered.full() || (packet.bulk && orderedBytes.load() >= maxIncomingBytes))
            return false;
        orderedBytes.fetch_add(packet.size(), std::memory_order_acq_rel);
        ordered.push(std::move(packet));
        ++published;
        return true;
    }
    std::optional<IncomingPacket> pop() {
        if (auto packet = ordered.pop()) {
            ++consumed;
            orderedBytes.fetch_sub(packet->size(), std::memory_order_acq_rel);
            return packet;
        }
        for (unsigned lane = 0; lane < laneCount; ++lane) {
            if (auto value = latest[lane].take())
                deferred[lane] = std::move(value);
            auto& value = deferred[lane];
            if (value && value->generation != generation.load(std::memory_order_acquire))
                value.reset();
            if (value && value->barrier <= consumed) {
                auto packet = std::move(value->packet);
                value.reset();
                return packet;
            }
        }
        return {};
    }
    // Consumer only; used after draining terminal connections.
    bool empty() const {
        if (!ordered.empty())
            return false;
        for (unsigned lane = 0; lane < laneCount; ++lane)
            if (deferred[lane] || !latest[lane].empty())
                return false;
        return true;
    }
    std::size_t queuedBytes() const {
        return orderedBytes.load(std::memory_order_acquire);
    }
};
} // namespace isaac::lan

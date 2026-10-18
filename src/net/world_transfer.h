#pragma once
#include "net/bulk_transfer.h"
#include "net/compression.h"
#include <chrono>
#include <deque>
#include <optional>

namespace isaac::lan {
// Entirely network-thread owned. A completed decode is published as a value;
// application acknowledgements still originate from the game thread.
class WorldTransfer {
  public:
    using Clock = std::chrono::steady_clock;
    static constexpr std::size_t maxCachedBytes = 8 * maxWorldSize;
    static constexpr std::size_t maxInFlightBytes = 65536;
    static constexpr std::size_t maxInFlightStates = 16;
    struct Cached {
        std::uint32_t tick;
        std::shared_ptr<const std::vector<std::uint8_t>> bytes;
        std::size_t wireBytes = 0;
        bool complete = false;
        Clock::time_point started = Clock::now();
    };
    struct Totals {
        std::uint64_t snapshots = 0, deltas = 0, raw = 0, wire = 0, full = 0;
    } totals;
    double compressMs = 0, prefixMs = 0, expandMs = 0;
    struct Trace {
        std::uint32_t tick = 0, base = 0;
        std::size_t raw = 0, wire = 0, full = 0;
        bool delta = false;
    } trace;

  private:
    std::optional<Cached> baseline;
    std::deque<Cached> flight, decoded;
    struct Receipt {
        std::uint32_t epoch, tick;
    };
    std::deque<Receipt> retired;
    std::optional<WorldState> pending, sending, assembling;
    std::size_t sent = 0, total = 0;
    std::uint32_t sendingBase = 0, receivingBase = 0, sendEpoch = 0;
    std::optional<std::uint32_t> lastDecoded;
    bool sendingDelta = false, receivingDelta = false;

  public:
    void resetSender() {
        for (const auto& value : flight)
            if (value.complete)
                retired.push_back({sendEpoch, value.tick});
        while (retired.size() > 2 * maxInFlightStates)
            retired.pop_front();
        baseline.reset();
        flight.clear();
        pending.reset();
        sending.reset();
    }
    void resetReceiver() {
        decoded.clear();
        assembling.reset();
        lastDecoded.reset();
    }
    void publish(WorldState value) {
        pending = std::move(value);
    }
    std::size_t cachedBytes() const {
        std::size_t size = baseline ? baseline->bytes->capacity() : 0;
        for (const auto* values : {&flight, &decoded})
            for (const auto& value : *values)
                size += value.bytes->capacity();
        return size;
    }
    std::size_t inFlightBytes() const {
        std::size_t size = 0;
        for (const auto& value : flight)
            size += value.wireBytes;
        return size;
    }
    std::size_t inFlightStates() const {
        return flight.size();
    }
    std::size_t worldBytes() const {
        std::size_t size = 0;
        for (const auto* value : {&pending, &sending, &assembling})
            if (*value)
                size += (*value)->bytes.capacity();
        return size;
    }
    std::uint64_t oldestMs() const {
        return flight.empty() ? 0
                              : std::chrono::duration_cast<std::chrono::milliseconds>(
                                    Clock::now() - flight.front().started)
                                    .count();
    }
    static std::size_t window(int minimumLatency) {
        return std::clamp<std::size_t>((std::max(0, minimumLatency) + 32) / 33 + 2, 4,
                                       maxInFlightStates);
    }
    bool canSend(int minimumLatency) const {
        return sending || (pending && flight.size() < window(minimumLatency) &&
                           inFlightBytes() < maxInFlightBytes &&
                           cachedBytes() + pending->bytes.capacity() <= maxCachedBytes);
    }
    bool acknowledge(std::uint32_t epoch, std::uint32_t tick) {
        if (epoch < sendEpoch)
            return false;
        const auto found = std::find_if(flight.begin(), flight.end(), [tick](const auto& value) {
            return value.tick == tick && value.complete;
        });
        if (found == flight.end() &&
            std::any_of(retired.begin(), retired.end(), [&](const auto& value) {
                return value.epoch == epoch && value.tick == tick;
            }))
            return false;
        if (found == flight.end() || epoch != sendEpoch)
            throw std::runtime_error("Receipt for an unsent state");
        baseline = *found;
        flight.erase(flight.begin(), std::next(found));
        return true;
    }
    void epoch(std::uint32_t value) {
        sendEpoch = value;
    }
    std::optional<Writer> next(StateCompression& codec, int minimumLatency) {
        if (!sending && pending) {
            if (flight.size() >= window(minimumLatency) || inFlightBytes() >= maxInFlightBytes ||
                cachedBytes() + pending->bytes.capacity() > maxCachedBytes)
                return {};
            sending = std::move(pending);
            pending.reset();
            sent = 0;
            const auto began = Clock::now();
            auto raw = std::make_shared<const std::vector<std::uint8_t>>(std::move(sending->bytes));
            auto full = codec.compress(*raw);
            const auto fullSize = full.size();
            sendingDelta = false;
            sendingBase = 0;
            prefixMs = 0;
            if (baseline) {
                const auto prefixBegan = Clock::now();
                auto delta = codec.compress(*raw, *baseline->bytes);
                prefixMs =
                    std::chrono::duration<double, std::milli>(Clock::now() - prefixBegan).count();
                if (delta.size() < full.size()) {
                    full = std::move(delta);
                    sendingDelta = true;
                    sendingBase = baseline->tick;
                }
            }
            totals.raw += raw->size();
            trace = {sending->tick, sendingBase, raw->size(), full.size(), fullSize, sendingDelta};
            totals.full += fullSize;
            totals.wire += full.size();
            ++totals.snapshots;
            totals.deltas += sendingDelta;
            sending->bytes = std::move(full);
            sendEpoch = sending->epoch;
            flight.push_back({sending->tick, std::move(raw), sending->bytes.size()});
            compressMs = std::chrono::duration<double, std::milli>(Clock::now() - began).count();
        }
        if (!sending)
            return {};
        const auto& value = *sending;
        Writer w(Message::world);
        w.u32(value.tick);
        w.u32(sent);
        w.u32(value.bytes.size());
        if (!sent) {
            w.u32(value.epoch);
            w.u8(sendingDelta);
            w.u32(sendingBase);
            w.u8(value.connected);
            w.u8(value.pauseOwner);
            w.u8(value.paused);
            for (const auto sequence : value.inputSequences)
                w.u32(sequence);
        }
        const auto chunk = bulkChunk(value.bytes, sent);
        w.blob(chunk);
        sent += chunk.size();
        if (sent == value.bytes.size()) {
            flight.back().complete = true;
            sending.reset();
        }
        return w;
    }
    std::optional<WorldState> receive(Reader& r, StateCompression& codec) {
        const auto tick = r.u32(), offset = r.u32(), size = r.u32();
        if (!offset) {
            if (!size || size > maxWorldSize + StateCompression::headerSize ||
                (lastDecoded && tick <= *lastDecoded))
                throw std::runtime_error("Invalid world state header");
            assembling = WorldState{};
            assembling->tick = tick;
            assembling->epoch = r.u32();
            const auto mode = r.u8();
            receivingBase = r.u32();
            if (mode > 1 || (!mode && receivingBase))
                throw std::runtime_error("Invalid world encoding header");
            receivingDelta = mode != 0;
            assembling->connected = r.u8();
            assembling->pauseOwner = r.u8();
            const auto paused = r.u8();
            if (!(assembling->connected & 1) || assembling->connected > allPlayersMask ||
                assembling->pauseOwner >= maxPlayers || paused > 1)
                throw std::runtime_error("Invalid world roster");
            assembling->paused = paused != 0;
            for (auto& sequence : assembling->inputSequences)
                sequence = r.u32();
            total = size;
        }
        if (!assembling || assembling->tick != tick || total != size)
            throw std::runtime_error("Invalid world state chunk");
        appendBulkChunk(assembling->bytes, total, offset, r.blob(bulkChunkSize),
                        maxWorldSize + StateCompression::headerSize);
        r.finish();
        if (assembling->bytes.size() != total)
            return {};
        const auto began = Clock::now();
        if (receivingDelta) {
            const auto found = std::find_if(decoded.begin(), decoded.end(), [&](const auto& value) {
                return value.tick == receivingBase;
            });
            if (found == decoded.end())
                throw std::runtime_error("World delta baseline is unavailable");
            assembling->bytes = codec.expand(assembling->bytes, *found->bytes);
        } else
            assembling->bytes = codec.expand(assembling->bytes);
        expandMs = std::chrono::duration<double, std::milli>(Clock::now() - began).count();
        decoded.push_back(
            {tick, std::make_shared<const std::vector<std::uint8_t>>(assembling->bytes)});
        while (decoded.size() > 2 * maxInFlightStates || cachedBytes() > maxCachedBytes)
            decoded.pop_front();
        lastDecoded = tick;
        auto result = std::move(assembling);
        assembling.reset();
        return result;
    }
};
} // namespace isaac::lan

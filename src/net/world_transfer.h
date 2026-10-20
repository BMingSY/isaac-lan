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
    static constexpr auto lostStateAge = std::chrono::milliseconds(500);
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
    std::optional<Cached> baseline, recovery;
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
    bool datagram;
    Clock::time_point fullAt{}, baselineAt{};

  public:
    explicit WorldTransfer(bool lossy = false) : datagram(lossy) {}
    void resetSender() {
        for (const auto& value : flight)
            if (value.complete)
                retired.push_back({sendEpoch, value.tick});
        while (retired.size() > 2 * maxInFlightStates)
            retired.pop_front();
        baseline.reset();
        recovery.reset();
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
    bool hasBaseline() const {
        return baseline.has_value();
    }
    std::size_t cachedBytes() const {
        std::size_t size = baseline ? baseline->bytes->capacity() : 0;
        if (recovery)
            size += recovery->bytes->capacity();
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
    static std::size_t window(int minimumLatency, bool lossy = false) {
        const auto pipeline = std::clamp<std::size_t>((std::max(0, minimumLatency) + 32) / 33 + 2,
                                                      4, maxInFlightStates);
        // Missing unreliable views consume no receiver receipt. Reserve room
        // for replacements without making the outstanding byte budget larger.
        return lossy ? std::min(maxInFlightStates, 2 * pipeline) : pipeline;
    }
    bool canSend(int minimumLatency) const {
        if (datagram && !flight.empty() && Clock::now() - flight.front().started >= lostStateAge)
            return pending.has_value();
        return sending || (pending && flight.size() < window(minimumLatency, datagram) &&
                           inFlightBytes() < maxInFlightBytes &&
                           cachedBytes() + pending->bytes.capacity() <= maxCachedBytes);
    }
    bool acknowledge(std::uint32_t epoch, std::uint32_t tick) {
        if (epoch < sendEpoch)
            return false;
        const auto found = std::find_if(flight.begin(), flight.end(), [tick](const auto& value) {
            return value.tick == tick && value.complete;
        });
        if (datagram && epoch == sendEpoch && recovery && recovery->tick == tick &&
            (!baseline || tick > baseline->tick)) {
            baseline = std::move(recovery);
            recovery.reset();
            baselineAt = Clock::now();
            while (!flight.empty() && flight.front().tick <= tick)
                flight.pop_front();
            return true;
        }
        if (found == flight.end() &&
            std::any_of(retired.begin(), retired.end(), [&](const auto& value) {
                return value.epoch == epoch && value.tick == tick;
            }))
            return false;
        if (datagram &&
            (found == flight.end() || epoch != sendEpoch || (baseline && tick <= baseline->tick)))
            return false;
        if (found == flight.end() || epoch != sendEpoch)
            throw std::runtime_error("Receipt for an unsent state");
        baseline = *found;
        baselineAt = Clock::now();
        flight.erase(flight.begin(), std::next(found));
        return true;
    }
    void epoch(std::uint32_t value) {
        sendEpoch = value;
    }
    void retainRecovery() {
        if (!flight.empty())
            recovery = flight.back();
    }
    std::optional<Writer> next(StateCompression& codec, int minimumLatency) {
        if (!sending && pending) {
            // Bound outstanding work even on a lossy link. Dropping a receipt
            // must not hold this window forever, but retiring every old frame
            // immediately would flood a congested path with newer snapshots.
            if (datagram) {
                while (!flight.empty() && Clock::now() - flight.front().started >= lostStateAge)
                    flight.pop_front();
            }
            if (flight.size() >= window(minimumLatency, datagram) ||
                inFlightBytes() >= maxInFlightBytes ||
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
            const bool keyframe = datagram && began - fullAt >= lostStateAge &&
                                  (!baseline || began - baselineAt >= lostStateAge);
            if (baseline && !keyframe) {
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
            if (!sendingDelta)
                fullAt = began;
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
        const auto chunk =
            datagram ? std::span<const std::uint8_t>(value.bytes) : bulkChunk(value.bytes, sent);
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
                (!datagram && lastDecoded && tick <= *lastDecoded))
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
        if (datagram) {
            auto bytes = r.blob(maxWorldSize + StateCompression::headerSize);
            if (offset || bytes.size() != total)
                throw std::runtime_error("Invalid datagram world size");
            assembling->bytes = std::move(bytes);
        } else
            appendBulkChunk(assembling->bytes, total, offset, r.blob(bulkChunkSize),
                            maxWorldSize + StateCompression::headerSize);
        r.finish();
        if (datagram && lastDecoded && tick <= *lastDecoded) {
            assembling.reset();
            return {};
        }
        if (assembling->bytes.size() != total)
            return {};
        const auto began = Clock::now();
        if (receivingDelta) {
            const auto found = std::find_if(decoded.begin(), decoded.end(), [&](const auto& value) {
                return value.tick == receivingBase;
            });
            if (found == decoded.end() && datagram) {
                assembling.reset();
                return {};
            }
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

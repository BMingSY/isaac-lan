#pragma once
#include "net/protocol.h"
#include <map>

namespace isaac::lan {
// Independent MTU-sized shards. Two parity shards recover any two erasures in
// each eight-data group, without retransmitting an obsolete realtime view.
class WorldShards {
  public:
    static constexpr std::size_t shardSize = 1024, dataShards = 8, parityShards = 2;
    static constexpr std::size_t maxSize = maxWorldSize + 128;
    static constexpr std::size_t maxBuffered = 4 * maxWorldSize, maxViews = 8;

  private:
    struct Field {
        std::array<std::uint8_t, 512> exp{};
        std::array<unsigned, 256> log{};
        Field() {
            unsigned value = 1;
            for (unsigned i = 0; i < 255; ++i) {
                exp[i] = value;
                log[value] = i;
                value <<= 1;
                if (value & 256)
                    value ^= 0x11d;
            }
            for (unsigned i = 255; i < exp.size(); ++i)
                exp[i] = exp[i - 255];
        }
        std::uint8_t multiply(std::uint8_t a, std::uint8_t b) const {
            return a && b ? exp[log[a] + log[b]] : 0;
        }
        std::uint8_t divide(std::uint8_t a, std::uint8_t b) const {
            return a ? exp[log[a] + 255 - log[b]] : 0;
        }
    };
    static const Field& field() {
        static const Field result;
        return result;
    }
    struct Group {
        std::uint16_t present = 0;
        unsigned count = 0;
        bool complete = false;
        std::array<std::array<std::uint8_t, shardSize>, parityShards> parity{};
    };
    struct View {
        std::size_t size = 0, remaining = 0;
        std::vector<std::uint8_t> bytes;
        std::vector<Group> groups;
        std::size_t memory() const {
            return bytes.capacity() + groups.capacity() * sizeof(Group);
        }
    };
    std::map<std::uint32_t, View> pending;
    std::optional<std::uint32_t> completed;

  public:
    static std::size_t packetCount(std::size_t bytes) {
        const auto shards = (bytes + shardSize - 1) / shardSize;
        const auto groups = (shards + dataShards - 1) / dataShards;
        return shards + groups * parityShards - (shards % dataShards == 1 ? 1 : 0);
    }
    std::size_t buffered() const {
        std::size_t result = 0;
        for (const auto& [id, view] : pending)
            result += view.memory();
        return result;
    }
    void reset() {
        pending.clear();
        completed.reset();
    }
    template <class Send>
    static void send(std::uint32_t id, std::span<const std::uint8_t> bytes, Send emit) {
        if (bytes.empty() || bytes.size() > maxSize)
            throw std::runtime_error("Invalid sharded world size");
        const auto shards = (bytes.size() + shardSize - 1) / shardSize;
        for (std::size_t first = 0; first < shards; first += dataShards) {
            const auto count = std::min(dataShards, shards - first);
            std::array<std::array<std::uint8_t, shardSize>, parityShards> parity{};
            const auto output = [&](unsigned index, std::span<const std::uint8_t> payload) {
                Writer packet(Message::world);
                packet.u32(id);
                packet.u32(bytes.size());
                packet.u16(first / dataShards);
                packet.u8(index);
                packet.bytes.insert(packet.bytes.end(), payload.begin(), payload.end());
                emit(std::span(packet.bytes).subspan(1));
            };
            for (unsigned i = 0; i < count; ++i) {
                const auto offset = (first + i) * shardSize;
                const auto data = bytes.subspan(offset, std::min(shardSize, bytes.size() - offset));
                for (std::size_t byte = 0; byte < data.size(); ++byte) {
                    parity[0][byte] ^= data[byte];
                    parity[1][byte] ^= field().multiply(data[byte], 1u << i);
                }
                output(i, data);
            }
            output(dataShards, parity[0]);
            if (count > 1)
                output(dataShards + 1, parity[1]);
        }
    }
    std::optional<std::vector<std::uint8_t>> receive(std::span<const std::uint8_t> packet) {
        Reader reader(packet);
        const auto id = reader.u32(), size = reader.u32();
        const auto groupIndex = reader.u16();
        const auto index = reader.u8();
        constexpr std::size_t headerSize = 11;
        if (!size || size > maxSize)
            throw std::runtime_error("Invalid sharded world length");
        const auto shards = (size + shardSize - 1) / shardSize;
        const auto first = groupIndex * dataShards;
        if (first >= shards)
            throw std::runtime_error("Invalid world shard group");
        const auto count = std::min(dataShards, shards - first);
        if (index >= dataShards + parityShards || (index >= count && index < dataShards) ||
            (count == 1 && index == dataShards + 1))
            throw std::runtime_error("Invalid world shard index");
        const auto offset = (first + index) * shardSize;
        const auto expected = index < count ? std::min(shardSize, size - offset) : shardSize;
        if (packet.size() != headerSize + expected)
            throw std::runtime_error("Invalid world shard payload");
        if (completed && id <= *completed)
            return {};
        auto found = pending.find(id);
        if (found == pending.end()) {
            View view;
            view.size = size;
            view.remaining = (shards + dataShards - 1) / dataShards;
            view.groups.resize(view.remaining);
            view.bytes.resize(shards * shardSize);
            while (!pending.empty() &&
                   (pending.size() >= maxViews || buffered() + view.memory() > maxBuffered)) {
                if (id < pending.begin()->first)
                    return {};
                pending.erase(pending.begin());
            }
            found = pending.emplace(id, std::move(view)).first;
        }
        auto& view = found->second;
        if (view.size != size)
            throw std::runtime_error("Conflicting world shard length");
        auto& group = view.groups[groupIndex];
        if (group.complete || (group.present & (1u << index)))
            return {};
        const auto payload = packet.subspan(headerSize);
        if (index < count)
            std::copy(payload.begin(), payload.end(), view.bytes.begin() + offset);
        else
            std::copy(payload.begin(), payload.end(), group.parity[index - dataShards].begin());
        group.present |= 1u << index;
        if (++group.count < count)
            return {};
        std::array<unsigned, parityShards> missing{};
        unsigned lost = 0;
        for (unsigned i = 0; i < count; ++i)
            if (!(group.present & (1u << i)))
                missing[lost++] = i;
        if (lost) {
            const bool haveXor = group.present & (1u << dataShards);
            for (std::size_t byte = 0; byte < shardSize; ++byte) {
                auto p = group.parity[0][byte], q = group.parity[1][byte];
                for (unsigned i = 0; i < count; ++i)
                    if (group.present & (1u << i)) {
                        const auto data = view.bytes[(first + i) * shardSize + byte];
                        p ^= data;
                        q ^= field().multiply(data, 1u << i);
                    }
                const auto a = missing[0];
                if (lost == 1)
                    view.bytes[(first + a) * shardSize + byte] =
                        haveXor ? p : field().divide(q, 1u << a);
                else {
                    const auto b = missing[1];
                    const auto value =
                        field().divide(q ^ field().multiply(p, 1u << b), (1u << a) ^ (1u << b));
                    view.bytes[(first + a) * shardSize + byte] = value;
                    view.bytes[(first + b) * shardSize + byte] = p ^ value;
                }
            }
        }
        group.complete = true;
        if (--view.remaining)
            return {};
        view.bytes.resize(size);
        auto result = std::move(view.bytes);
        completed = id;
        pending.erase(pending.begin(), std::next(found));
        return result;
    }
};
} // namespace isaac::lan

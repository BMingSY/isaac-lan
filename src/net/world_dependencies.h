#pragma once
#include "net/protocol.h"
#include <deque>
#include <optional>

namespace isaac::lan {
// Byte dependencies are scoped to a transport generation. A missing revision
// never produces a partially restored view; keep only the newest waiting view.
class WorldDependencies {
    struct Entry {
        std::uint32_t revision;
        std::vector<std::uint8_t> bytes;
    };
    std::deque<Entry> entries;
    std::optional<WorldState> pending;
    std::optional<std::uint32_t> delivered;
    std::uint32_t latest = 0;
    static constexpr std::size_t maxEntries = 32, maxBytes = 4 * maxWorldSize;

    std::optional<WorldState> ready() {
        if (!pending)
            return {};
        if (pending->revision) {
            const auto found = std::find_if(entries.begin(), entries.end(), [&](const auto& entry) {
                return entry.revision == pending->revision;
            });
            if (found == entries.end()) {
                if (pending->revision <= latest)
                    pending.reset();
                return {};
            }
            if (pending->bytes.size() + found->bytes.size() + sizeof(std::uint32_t) > maxWorldSize)
                throw std::runtime_error("World dependency size exceeded");
            pending->stable = found->bytes;
        }
        delivered = pending->tick;
        auto result = std::move(pending);
        pending.reset();
        return result;
    }

  public:
    std::span<const std::uint8_t> latestBytes() const {
        return entries.empty() ? std::span<const std::uint8_t>{} : entries.back().bytes;
    }
    std::size_t cachedBytes() const {
        std::size_t bytes = pending ? pending->bytes.capacity() : 0;
        for (const auto& entry : entries)
            bytes += entry.bytes.capacity();
        return bytes;
    }
    void reset() {
        entries.clear();
        pending.reset();
        delivered.reset();
        latest = 0;
    }
    std::optional<WorldState> receive(std::uint32_t revision, std::vector<std::uint8_t> bytes) {
        if (!revision || revision != latest + 1 || bytes.empty() || bytes.size() > maxWorldSize)
            throw std::runtime_error("Invalid world dependency revision");
        latest = revision;
        entries.push_back({revision, std::move(bytes)});
        while (entries.size() > maxEntries || cachedBytes() > maxBytes)
            entries.pop_front();
        return ready();
    }
    std::optional<WorldState> receive(WorldState value) {
        if (!value.stable.empty())
            throw std::runtime_error("Unexpected inline UDP dependency");
        if ((delivered && value.tick <= *delivered) || (pending && value.tick <= pending->tick))
            return {};
        pending = std::move(value);
        return ready();
    }
};
} // namespace isaac::lan

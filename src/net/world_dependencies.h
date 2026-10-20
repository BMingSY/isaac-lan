#pragma once
#include "net/protocol.h"
#include <map>
#include <optional>

namespace isaac::lan {
// Byte dependencies are scoped to a transport generation. A missing revision
// never produces a partially restored view; keep only the newest waiting view.
class WorldDependencies {
    std::map<std::uint32_t, std::vector<std::uint8_t>> entries;
    std::optional<WorldState> pending;
    std::optional<std::uint32_t> delivered;
    std::uint32_t latest = 0;
    static constexpr std::size_t maxEntries = 32, maxBytes = 4 * maxWorldSize;

    std::optional<WorldState> ready() {
        if (!pending)
            return {};
        if (pending->revision) {
            const auto found = entries.find(pending->revision);
            if (found == entries.end()) {
                if (pending->revision <= latest)
                    pending.reset();
                return {};
            }
            if (pending->bytes.size() + found->second.size() + sizeof(std::uint32_t) > maxWorldSize)
                throw std::runtime_error("World dependency size exceeded");
            pending->stable = found->second;
        }
        delivered = pending->tick;
        auto result = std::move(pending);
        pending.reset();
        return result;
    }

    void remember(std::uint32_t revision, std::vector<std::uint8_t> bytes) {
        if (!revision || bytes.empty() || bytes.size() > maxWorldSize)
            throw std::runtime_error("Invalid world dependency revision");
        if (const auto found = entries.find(revision); found != entries.end()) {
            if (found->second != bytes)
                throw std::runtime_error("Conflicting world dependency revision");
            return;
        }
        latest = std::max(latest, revision);
        entries.emplace(revision, std::move(bytes));
        while (entries.size() > maxEntries || cachedBytes() > maxBytes)
            entries.erase(entries.begin());
    }

  public:
    std::size_t cachedBytes() const {
        std::size_t bytes = pending ? pending->bytes.capacity() : 0;
        for (const auto& entry : entries)
            bytes += entry.second.capacity();
        return bytes;
    }
    void reset() {
        entries.clear();
        pending.reset();
        delivered.reset();
        latest = 0;
    }
    std::optional<WorldState> receive(std::uint32_t revision, std::vector<std::uint8_t> bytes) {
        remember(revision, std::move(bytes));
        return ready();
    }
    std::optional<WorldState> receive(WorldState value) {
        if ((delivered && value.tick <= *delivered) || (pending && value.tick <= pending->tick))
            return {};
        if (!value.stable.empty())
            remember(value.revision, std::move(value.stable));
        pending = std::move(value);
        return ready();
    }
};
} // namespace isaac::lan

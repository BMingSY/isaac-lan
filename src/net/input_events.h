#pragma once
#include "net/messages.h"
#include <map>

namespace isaac::lan {
// Reliable events and their short-lived realtime copies share an ordinal.
// Wait for missing predecessors, then consume each press on its own host update.
class InputEvents {
    static constexpr std::uint32_t repeatSampleAge = 12, maxSampleAge = 120, maxPending = 128;
    std::uint32_t sent = 0, consumed = 0;
    std::vector<InputEvent> repeated;
    std::map<std::uint32_t, InputSample> pending;

  public:
    std::optional<InputEvent> submit(const InputSample& sample) {
        std::erase_if(repeated, [&](const auto& event) {
            return sample.sequence - event.sample.sequence > repeatSampleAge;
        });
        if (!sample.input.triggered)
            return {};
        if (repeated.size() == maxRepeatedInputEvents)
            repeated.erase(repeated.begin());
        repeated.push_back({++sent, sample});
        return repeated.back();
    }
    std::span<const InputEvent> recent() const {
        return repeated;
    }
    void receive(const InputEvent& event) {
        if (!event.id || !event.sample.input.triggered)
            throw std::runtime_error("Invalid input event");
        if (event.id <= consumed)
            return;
        if (event.id - consumed > maxPending)
            throw std::runtime_error("Input event queue limit exceeded");
        pending.try_emplace(event.id, event.sample);
    }
    std::uint16_t consume(std::uint32_t sequence, const std::optional<InputRoom>& room,
                          bool fresh) {
        while (!pending.empty()) {
            auto first = pending.begin();
            const auto& sample = first->second;
            if (first->first != consumed + 1 || sample.sequence > sequence)
                break;
            std::uint16_t edges = 0;
            if (fresh && sequence - sample.sequence <= maxSampleAge &&
                (!room || !sample.room || room->epoch == sample.room->epoch))
                edges = retainedInputEdges(sample.input, sample.room, room);
            ++consumed;
            pending.erase(first);
            if (edges)
                return edges;
        }
        return 0;
    }
};
} // namespace isaac::lan

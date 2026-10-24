#pragma once
#include "net/messages.h"
#include <deque>

namespace isaac::lan {
// Whole messages awaiting handoff. Replace only adjacent held-input samples;
// one-shot input events and control messages retain their order.
struct SendQueue {
    std::deque<std::vector<std::uint8_t>> outgoing;
    std::size_t queued = 0;
    std::uint64_t coalescedInputs = 0;
    std::span<const std::uint8_t> unsentTail(Message type) const {
        if (outgoing.empty() || outgoing.back().front() != static_cast<unsigned>(type))
            return {};
        return outgoing.back();
    }
    void append(std::vector<std::uint8_t> bytes) {
        if (bytes.at(0) == static_cast<unsigned>(Message::input) &&
            !unsentTail(Message::input).empty()) {
            queued -= outgoing.back().size();
            outgoing.pop_back();
            ++coalescedInputs;
        }
        queued += bytes.size();
        outgoing.push_back(std::move(bytes));
    }
};
} // namespace isaac::lan

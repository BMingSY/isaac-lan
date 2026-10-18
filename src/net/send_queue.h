#pragma once
#include "net/messages.h"
#include <deque>

namespace isaac::lan {
// Ordered framed bytes. Shared by the handoff and socket owner so input
// coalescing obeys exactly the same partial-send and reliable-message boundary.
struct SendQueue {
    std::deque<std::vector<std::uint8_t>> outgoing;
    std::size_t sent = 0, queued = 0;
    std::uint64_t coalescedInputs = 0;
    std::span<const std::uint8_t> unsentTail(Message type) const {
        if (outgoing.empty() || (outgoing.size() == 1 && sent) ||
            outgoing.back()[2] != static_cast<unsigned>(type))
            return {};
        return std::span<const std::uint8_t>(outgoing.back()).subspan(2);
    }
    std::size_t append(std::vector<std::uint8_t> bytes) {
        std::size_t removed = 0;
        if (bytes.at(2) == static_cast<unsigned>(Message::input)) {
            const auto tail = unsentTail(Message::input);
            if (!tail.empty()) {
                Reader oldReader(tail.subspan(1));
                Reader nextReader(std::span<const std::uint8_t>(bytes).subspan(3));
                const auto previous = readInput(oldReader);
                auto next = readInput(nextReader);
                oldReader.finish();
                nextReader.finish();
                next.input.triggered |=
                    retainedInputEdges(previous.input, previous.room, next.room);
                auto message = inputMessage(next).bytes;
                const auto size = message.size();
                message.insert(message.begin(), {static_cast<std::uint8_t>(size >> 8),
                                                 static_cast<std::uint8_t>(size)});
                bytes = std::move(message);
                removed = outgoing.back().size();
                outgoing.pop_back();
                queued -= removed;
                ++coalescedInputs;
            }
        }
        queued += bytes.size();
        outgoing.push_back(std::move(bytes));
        return removed;
    }
    void advance(std::size_t count) {
        if (outgoing.empty() || count > outgoing.front().size() - sent)
            throw std::runtime_error("Invalid socket send progress");
        sent += count;
        queued -= count;
        if (sent == outgoing.front().size()) {
            outgoing.pop_front();
            sent = 0;
        }
    }
};
} // namespace isaac::lan

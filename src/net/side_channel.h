#pragma once
#include "net/protocol.h"
#include <chrono>

namespace isaac::lan {
// Independent bounded mailboxes: interface traffic must not consume a Mod's
// action queue or be coalesced with world snapshots.
struct SideChannel {
    std::vector<IntegrationMessage> queue;
    std::array<unsigned, maxPlayers> counts{};
    std::chrono::steady_clock::time_point window = std::chrono::steady_clock::now();

    bool receive(unsigned sender, std::string bytes) {
        const auto now = std::chrono::steady_clock::now();
        if (now - window >= std::chrono::seconds(1)) {
            window = now;
            counts = {};
        }
        if (sender >= maxPlayers || ++counts[sender] > messagesPerSecond)
            return false;
        return enqueue(sender, std::move(bytes));
    }
    bool enqueue(unsigned sender, std::string bytes) {
        if (sender >= maxPlayers ||
            std::count_if(queue.begin(), queue.end(), [sender](const auto& item) {
                return item.sender == sender;
            }) >= static_cast<std::ptrdiff_t>(maxIntegrationQueue))
            return false;
        queue.push_back({sender, std::move(bytes)});
        return true;
    }
    std::optional<IntegrationMessage> take() {
        if (queue.empty())
            return {};
        auto result = std::move(queue.front());
        queue.erase(queue.begin());
        return result;
    }
    static constexpr unsigned messagesPerSecond = 64;
};
} // namespace isaac::lan

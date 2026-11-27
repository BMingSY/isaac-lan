#pragma once
#include "net/datagram_route.h"
#include <algorithm>
#include <deque>
#include <map>
#include <mutex>
#include <vector>

// A deterministic platform carrier for the real ENet workers. The claimed
// local account can differ from the authenticated source to test admission.
struct AccountDatagrams final : isaac::lan::DatagramRoute {
    struct Packet {
        std::uint64_t source;
        std::vector<std::uint8_t> bytes;
    };
    struct Network {
        std::mutex mutex;
        std::map<std::uint64_t, std::deque<Packet>> queues;
    };
    std::shared_ptr<Network> network;
    std::uint64_t host, source, identity;
    AccountDatagrams(std::shared_ptr<Network> bus, std::uint64_t owner, std::uint64_t remote,
                     std::uint64_t claimed)
        : network(std::move(bus)), host(owner), source(remote), identity(claimed) {}
    std::uint64_t localAccount() const override {
        return identity;
    }
    std::uint64_t hostAccount() const override {
        return host;
    }
    State state() override {
        return State::connected;
    }
    std::shared_ptr<DatagramRoute> reconnect() override {
        return std::make_shared<AccountDatagrams>(network, host, source, identity);
    }
    int send(std::uint64_t destination, std::span<const std::uint8_t> bytes) override {
        std::lock_guard lock(network->mutex);
        network->queues[destination].push_back({source, {bytes.begin(), bytes.end()}});
        return bytes.size();
    }
    int receive(std::uint64_t& sender, std::span<std::uint8_t> bytes) override {
        std::lock_guard lock(network->mutex);
        auto& queue = network->queues[source];
        if (queue.empty())
            return 0;
        auto packet = std::move(queue.front());
        queue.pop_front();
        if (packet.bytes.size() > bytes.size())
            return -2;
        sender = packet.source;
        std::copy(packet.bytes.begin(), packet.bytes.end(), bytes.begin());
        return packet.bytes.size();
    }
};

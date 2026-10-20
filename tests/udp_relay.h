#pragma once
#include <winsock2.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

// Real datagrams, not a TCP pause proxy. This fixture owns one loopback route.
class UdpRelay {
    SOCKET socket = INVALID_SOCKET;
    sockaddr_in target{}, client{};
    std::atomic<bool> stopping{false};
    std::thread worker;
    struct Packet {
        std::chrono::steady_clock::time_point at;
        sockaddr_in destination;
        std::vector<char> bytes;
    };
    void run() {
        using Clock = std::chrono::steady_clock;
        std::vector<Packet> pending;
        unsigned counter = 0;
        while (!stopping.load()) {
            for (unsigned count = 0; count < 256; ++count) {
                std::array<char, 65536> buffer;
                sockaddr_in from{};
                int length = sizeof(from);
                const auto size = recvfrom(socket, buffer.data(), buffer.size(), 0,
                                           reinterpret_cast<sockaddr*>(&from), &length);
                if (size < 0)
                    break;
                const bool downstream = from.sin_port == target.sin_port;
                if (!downstream)
                    client = from;
                if (!client.sin_port)
                    continue;
                ++counter;
                ++received;
                maxBytes.store(std::max<unsigned>(maxBytes.load(), size));
                if (impaired.load() && counter % 7 == 0) {
                    ++dropped;
                    continue;
                }
                const auto lag = impaired.load() ? (counter % 3 == 0 ? 55 : 10) : 0;
                Packet packet{Clock::now() + std::chrono::milliseconds(lag),
                              downstream ? client : target,
                              {buffer.begin(), buffer.begin() + size}};
                if (impaired.load() && counter % 5 == 0) {
                    pending.push_back(packet);
                    ++duplicated;
                }
                pending.push_back(std::move(packet));
            }
            std::stable_sort(pending.begin(), pending.end(),
                             [](const auto& a, const auto& b) { return a.at < b.at; });
            while (!pending.empty() && pending.front().at <= Clock::now()) {
                auto& packet = pending.front();
                sendto(socket, packet.bytes.data(), packet.bytes.size(), 0,
                       reinterpret_cast<const sockaddr*>(&packet.destination),
                       sizeof(packet.destination));
                pending.erase(pending.begin());
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }

  public:
    std::atomic<bool> impaired{false};
    std::atomic<unsigned> received{0}, dropped{0}, duplicated{0}, maxBytes{0};
    std::uint16_t port = 0;
    explicit UdpRelay(std::uint16_t destination) {
        socket = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        int length = sizeof(address);
        if (socket == INVALID_SOCKET ||
            bind(socket, reinterpret_cast<sockaddr*>(&address), sizeof(address)) ||
            getsockname(socket, reinterpret_cast<sockaddr*>(&address), &length))
            throw std::runtime_error("Cannot bind UDP fixture");
        port = ntohs(address.sin_port);
        target = address;
        target.sin_port = htons(destination);
        u_long mode = 1;
        ioctlsocket(socket, FIONBIO, &mode);
        worker = std::thread([this] { run(); });
    }
    ~UdpRelay() {
        stopping.store(true);
        worker.join();
        closesocket(socket);
    }
};

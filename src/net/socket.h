#pragma once
#include "net/protocol.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <deque>

namespace isaac::lan {
struct ConnectionLost : std::runtime_error {
    using std::runtime_error::runtime_error;
};
inline bool wouldBlock() {
    return WSAGetLastError() == WSAEWOULDBLOCK;
}
inline void configure(SOCKET s) {
    u_long mode = 1;
    if (ioctlsocket(s, FIONBIO, &mode) != 0)
        throw std::runtime_error("Cannot set nonblocking socket");
    BOOL on = TRUE;
    if (setsockopt(s, IPPROTO_TCP, TCP_NODELAY, reinterpret_cast<const char*>(&on), sizeof(on)) !=
        0)
        throw std::runtime_error("Cannot disable TCP buffering");
}
// Owns a socket and bounded framed-byte queues, never game or peer policy.
struct Socket {
    SOCKET handle = INVALID_SOCKET;
    std::vector<std::uint8_t> received;
    std::deque<std::vector<std::uint8_t>> outgoing;
    std::size_t sent = 0, queued = 0;
    bool finished = false;
    explicit Socket(SOCKET value = INVALID_SOCKET) : handle(value) {}
    Socket(const Socket&) = delete;
    Socket& operator=(const Socket&) = delete;
    ~Socket() {
        if (handle != INVALID_SOCKET)
            closesocket(handle);
    }
    void sendMessage(const Writer& w) {
        if (w.bytes.empty() || w.bytes.size() > maxMessageSize || queued + w.bytes.size() > 262144)
            throw std::runtime_error("Network queue limit exceeded");
        std::vector<std::uint8_t> data;
        auto size = static_cast<std::uint16_t>(w.bytes.size());
        data.push_back(size >> 8);
        data.push_back(size & 255);
        data.insert(data.end(), w.bytes.begin(), w.bytes.end());
        queued += data.size();
        outgoing.push_back(std::move(data));
    }
    void flush() {
        while (!outgoing.empty()) {
            auto& data = outgoing.front();
            int n = ::send(handle, reinterpret_cast<const char*>(data.data() + sent),
                           static_cast<int>(data.size() - sent), 0);
            if (n == SOCKET_ERROR) {
                if (wouldBlock())
                    return;
                throw ConnectionLost("Peer send failed");
            }
            if (n <= 0)
                throw ConnectionLost("Peer closed connection");
            sent += n;
            queued -= n;
            if (sent == data.size()) {
                outgoing.pop_front();
                sent = 0;
            }
        }
    }
    template <class F> void receive(F callback) {
        std::array<std::uint8_t, 8192> buffer;
        // Bound each poll so one peer cannot monopolize the engine thread.
        for (unsigned chunk = 0; chunk < 8; ++chunk) {
            int n = recv(handle, reinterpret_cast<char*>(buffer.data()),
                         static_cast<int>(buffer.size()), 0);
            if (n == SOCKET_ERROR) {
                if (wouldBlock())
                    break;
                throw ConnectionLost("Peer receive failed");
            }
            if (!n) {
                if (finished)
                    return;
                throw ConnectionLost("Peer disconnected");
            }
            received.insert(received.end(), buffer.begin(), buffer.begin() + n);
            std::size_t consumed = 0;
            while (received.size() - consumed >= 2) {
                auto size =
                    static_cast<unsigned>((received[consumed] << 8) | received[consumed + 1]);
                if (!size || size > maxMessageSize)
                    throw std::runtime_error("Invalid network message size");
                if (received.size() - consumed < size + 2)
                    break;
                Reader reader{std::span<const std::uint8_t>(received).subspan(consumed + 2, size)};
                callback(reader);
                reader.finish();
                consumed += size + 2;
            }
            received.erase(received.begin(), received.begin() + consumed);
            if (received.size() > maxMessageSize + 2)
                throw std::runtime_error("Receive buffer limit exceeded");
        }
    }
};
} // namespace isaac::lan

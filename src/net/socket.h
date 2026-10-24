#pragma once
#include "net/protocol.h"
#include "net/network_io.h"
#include "net/send_queue.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <deque>

namespace isaac::lan {
struct ConnectionLost : std::runtime_error {
    using std::runtime_error::runtime_error;
};
// Main-thread message handoff; the ENet worker owns the endpoint.
struct Socket : SendQueue {
    std::shared_ptr<NetworkIo> io;
    std::shared_ptr<ConnectionPipe> pipe;
    bool finished = false;
    Socket() = default;
    Socket(std::shared_ptr<NetworkIo> worker, std::shared_ptr<ConnectionPipe> connection)
        : io(std::move(worker)), pipe(std::move(connection)) {}
    Socket(const Socket&) = delete;
    Socket& operator=(const Socket&) = delete;
    ~Socket() {
        if (pipe) {
            pipe->closing.store(true, std::memory_order_release);
            io->signal();
        }
    }
    std::size_t queuedBytes() const {
        return queued + (pipe ? pipe->queued.load(std::memory_order_acquire) : 0);
    }
    bool sendTransfer(std::shared_ptr<const ReliableTransfer> transfer) {
        flush();
        if (!outgoing.empty() || !pipe->outgoing.push({{}, std::move(transfer)}))
            return false;
        io->signal();
        return true;
    }
    void sendMessage(const Writer& w) {
        if (w.bytes.empty() || w.bytes.size() > maxMessageSize ||
            queuedBytes() + w.bytes.size() > maxSocketQueueBytes)
            throw std::runtime_error("Network queue limit exceeded");
        append(w.bytes);
        if (pipe)
            flush();
    }
    void flush() {
        if (pipe) {
            while (!outgoing.empty() && !pipe->outgoing.full()) {
                auto message = std::move(outgoing.front());
                outgoing.pop_front();
                queued -= message.size();
                pipe->queued.fetch_add(message.size(), std::memory_order_acq_rel);
                pipe->outgoing.push({std::move(message), {}});
            }
            io->signal();
            return;
        }
    }
    template <class F, class W = std::nullptr_t, class B = std::nullptr_t>
    void receive(F callback, W world = nullptr, const std::function<bool()>& paused = {},
                 B bulk = nullptr) {
        if (pipe) {
            for (unsigned count = 0; count < 128; ++count) {
                if (paused && paused())
                    break;
                auto message = pipe->incoming.pop();
                if (!message)
                    break;
                pipe->incomingBytes.fetch_sub(message->size(), std::memory_order_acq_rel);
                if (message->bulk) {
                    if constexpr (std::is_same_v<B, std::nullptr_t>)
                        throw std::runtime_error("Unexpected bulk transfer before handshake");
                    else
                        bulk(std::move(*message->bulk));
                } else if (message->world) {
                    if constexpr (std::is_same_v<W, std::nullptr_t>)
                        throw std::runtime_error("Unexpected world before handshake");
                    else
                        world(std::move(*message->world));
                } else {
                    Reader reader(message->bytes);
                    callback(reader);
                    reader.finish();
                }
            }
            io->signal();
            const auto status = pipe->state.load(std::memory_order_acquire);
            if (pipe->incoming.empty() && !finished &&
                (status == ConnectionPipe::closed || status == ConnectionPipe::failed))
                throw ConnectionLost(status == ConnectionPipe::failed ? pipe->error
                                                                      : "Peer disconnected");
            return;
        }
        throw std::runtime_error("No attached network connection");
    }
};
} // namespace isaac::lan

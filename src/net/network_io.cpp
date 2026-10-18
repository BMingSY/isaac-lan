#include "net/network_io.h"
#include "net/messages.h"
#include "net/world_transfer.h"
#include "net/wire_codec.h"
#include "net/send_queue.h"
#include <algorithm>
#include <chrono>

namespace isaac::lan {
namespace {
using Clock = std::chrono::steady_clock;
constexpr auto closeGrace = std::chrono::milliseconds(250);
constexpr std::size_t receiveBudget = 65536;
bool blocked() {
    return WSAGetLastError() == WSAEWOULDBLOCK;
}
std::vector<std::uint8_t> frame(std::vector<std::uint8_t> message, StateCompression& codec) {
    message = encodeWire(std::move(message), codec);
    if (message.empty() || message.size() > maxMessageSize)
        throw std::runtime_error("Invalid outgoing message size");
    const auto size = message.size();
    message.insert(message.begin(),
                   {static_cast<std::uint8_t>(size >> 8), static_cast<std::uint8_t>(size)});
    return message;
}
} // namespace
struct NetworkIo::Connection {
    std::shared_ptr<ConnectionPipe> pipe;
    WSAEVENT event = WSACreateEvent();
    SendQueue sending;
    struct Bulk {
        std::shared_ptr<const ReliableTransfer> transfer;
        std::size_t offset = 0;
        bool started = false;
    };
    std::deque<Bulk> bulk;
    std::vector<std::uint8_t> received;
    WorldGeneration generation;
    bool again = false;
    bool halfClosed = false;
    WorldTransfer world;
    ReliableReceiver reliable;
    std::optional<Clock::time_point> closingAt;
    explicit Connection(std::shared_ptr<ConnectionPipe> value) : pipe(std::move(value)) {
        BOOL enabled = TRUE;
        if (event == WSA_INVALID_EVENT ||
            setsockopt(pipe->handle, IPPROTO_TCP, TCP_NODELAY,
                       reinterpret_cast<const char*>(&enabled), sizeof(enabled)) ||
            WSAEventSelect(pipe->handle, event, FD_CONNECT | FD_READ | FD_WRITE | FD_CLOSE)) {
            pipe->error = "Cannot configure background socket";
            pipe->state.store(ConnectionPipe::failed, std::memory_order_release);
        } else if (pipe->address) {
            const auto status =
                connect(pipe->handle, reinterpret_cast<const sockaddr*>(&*pipe->address),
                        sizeof(sockaddr_in));
            if (!status)
                pipe->state.store(ConnectionPipe::connected, std::memory_order_release);
            else if (!blocked()) {
                pipe->error = "Host connection refused";
                pipe->state.store(ConnectionPipe::failed, std::memory_order_release);
            }
        }
    }
    ~Connection() {
        closesocket(pipe->handle);
        if (event != WSA_INVALID_EVENT)
            WSACloseEvent(event);
        pipe->queued.store(0, std::memory_order_release);
    }
    void synchronizeSender() {
        const auto requested = pipe->generation.load(std::memory_order_acquire);
        if (requested != generation) {
            generation = requested;
            world.resetSender();
            world.epoch(generation.epoch);
        }
    }
    bool service(StateCompression& codec, StateCompression& worldCodec) {
        again = false;
        if (pipe->state.load(std::memory_order_acquire) == ConnectionPipe::failed)
            return false;
        WSANETWORKEVENTS events{};
        if (WSAEnumNetworkEvents(pipe->handle, event, &events))
            throw std::runtime_error("Cannot inspect socket events");
        if (events.lNetworkEvents & FD_CONNECT) {
            if (events.iErrorCode[FD_CONNECT_BIT])
                throw std::runtime_error("Host connection refused");
            pipe->state.store(ConnectionPipe::connected, std::memory_order_release);
        }
        if (pipe->closing.load(std::memory_order_acquire) && !closingAt)
            closingAt = Clock::now();
        if (pipe->state.load(std::memory_order_acquire) == ConnectionPipe::connecting)
            return !closingAt;
        synchronizeSender();
        while (auto packet = pipe->outgoing.pop()) {
            if (packet->transfer) {
                if (bulk.size() >= 4)
                    throw std::runtime_error("Reliable transaction queue limit exceeded");
                pipe->bulkBytes.fetch_add(packet->transfer->size());
                bulk.push_back({std::move(packet->transfer)});
                continue;
            }
            const auto& message = packet->bytes;
            const auto type = static_cast<Message>(message.at(0));
            if (type == Message::ending || type == Message::finish || type == Message::error ||
                type == Message::restart || type == Message::goodbye) {
                bulk.clear();
                pipe->bulkBytes.store(0);
            }
            auto bytes = frame(message, codec);
            // Producer accounts uncompressed bytes plus framing. Compression
            // can add its fixed envelope, so adjust the observed backlog here.
            const auto original = message.size() + 2;
            if (bytes.size() >= original)
                pipe->queued.fetch_add(bytes.size() - original, std::memory_order_acq_rel);
            else
                pipe->queued.fetch_sub(original - bytes.size(), std::memory_order_acq_rel);
            pipe->queued.fetch_sub(sending.append(std::move(bytes)));
            pipe->coalescedInputs.store(sending.coalescedInputs);
        }
        if (auto publication = pipe->publication.take()) {
            // A new floor publication can arrive after the first check above.
            // Adopt its generation before deciding whether the value is stale.
            synchronizeSender();
            if (publication->generation == generation)
                world.publish(std::move(publication->value));
        }
        const auto before = world.totals.snapshots;
        for (unsigned part = 0; !closingAt && part < 8 && pipe->queued.load() < 16384; ++part) {
            std::optional<Writer> message;
            if (!bulk.empty()) {
                auto& current = bulk.front();
                if (!current.started && !current.transfer->header.empty()) {
                    auto header = frame(current.transfer->header, codec);
                    pipe->queued.fetch_add(header.size());
                    sending.append(std::move(header));
                }
                current.started = true;
                message = current.transfer->chunk(current.offset);
                current.offset +=
                    std::min(bulkChunkSize, current.transfer->size() - current.offset);
                if (current.transfer->checkpoint)
                    pipe->checkpointSent.store(current.offset, std::memory_order_release);
                if (current.offset == current.transfer->size()) {
                    pipe->bulkBytes.fetch_sub(current.transfer->size());
                    bulk.pop_front();
                }
            } else
                message = world.next(worldCodec, pipe->minimumLatency.load());
            if (!message)
                break;
            auto bytes = frame(std::move(message->bytes), codec);
            pipe->queued.fetch_add(bytes.size(), std::memory_order_acq_rel);
            pipe->queued.fetch_sub(sending.append(std::move(bytes)));
            pipe->coalescedInputs.store(sending.coalescedInputs);
        }
        if (world.totals.snapshots != before) {
            pipe->samples.push({"compress", world.compressMs});
            pipe->samples.push({"delta.encode", world.prefixMs});
            if (world.trace.tick % 300 == 0)
                pipe->traces.push(WorldTransfer::Trace(world.trace));
        }
        while (!sending.outgoing.empty()) {
            auto& bytes = sending.outgoing.front();
            const auto n =
                ::send(pipe->handle, reinterpret_cast<const char*>(bytes.data() + sending.sent),
                       static_cast<int>(bytes.size() - sending.sent), 0);
            if (n == SOCKET_ERROR && blocked())
                break;
            if (n <= 0)
                throw std::runtime_error("Peer send failed");
            sending.advance(n);
            pipe->queued.fetch_sub(n, std::memory_order_acq_rel);
        }
        if (closingAt) {
            if (sending.outgoing.empty() && !halfClosed) {
                shutdown(pipe->handle, SD_SEND);
                halfClosed = true;
            }
            if (Clock::now() - *closingAt >= closeGrace) {
                pipe->state.store(ConnectionPipe::closed, std::memory_order_release);
                return false;
            }
            // Drain the peer's outstanding input/receipts after half-close.
            // Closing with unread data can reset TCP and lose the final event.
            std::array<char, 8192> discard;
            for (unsigned part = 0; part < 8; ++part) {
                const auto n = recv(pipe->handle, discard.data(), discard.size(), 0);
                if (n == SOCKET_ERROR && blocked())
                    break;
                if (n <= 0) {
                    pipe->state.store(ConnectionPipe::closed, std::memory_order_release);
                    return false;
                }
            }
            return true;
        }
        std::size_t read = 0;
        while (!pipe->incoming.full() && pipe->incomingBytes.load() < maxIncomingBytes) {
            if (received.size() >= 2) {
                const auto size = static_cast<std::size_t>((received[0] << 8) | received[1]);
                if (!size || size > maxMessageSize)
                    throw std::runtime_error("Invalid network message size");
                if (received.size() >= size + 2) {
                    auto bytes =
                        decodeWire(std::span<const std::uint8_t>(received).subspan(2, size), codec);
                    IncomingPacket packet;
                    const auto type = static_cast<Message>(bytes[0]);
                    if (type == Message::world) {
                        Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
                        packet.world = world.receive(r, worldCodec);
                        if (packet.world)
                            pipe->samples.push({"decompress", world.expandMs});
                    } else if (type == Message::snapshot) {
                        Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
                        packet.bulk = reliable.snapshot(r);
                    } else if (type == Message::stage) {
                        Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
                        packet.bulk = reliable.floor(r);
                        if (packet.bulk)
                            world.resetReceiver();
                    } else if (type == Message::ping && pipe->answerPing.load()) {
                        Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
                        Writer pong(Message::pong);
                        pong.u32(r.u32());
                        r.finish();
                        auto response = frame(std::move(pong.bytes), codec);
                        pipe->queued.fetch_add(response.size());
                        sending.append(std::move(response));
                        again = true;
                    } else {
                        bool deliver = true;
                        if (type == Message::applied) {
                            Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
                            const auto epoch = r.u32(), tick = r.u32();
                            r.finish();
                            deliver = world.acknowledge(epoch, tick);
                        }
                        if (type == Message::start || type == Message::restart ||
                            type == Message::ending || type == Message::returnLobby) {
                            world.resetReceiver();
                            reliable.reset();
                        }
                        if (type == Message::start || type == Message::restart) {
                            Reader r(std::span<const std::uint8_t>(bytes).subspan(1));
                            reliable.begin(readStart(r));
                            r.finish();
                        }
                        if (deliver)
                            packet.bytes = std::move(bytes);
                    }
                    if (packet.size()) {
                        pipe->incomingBytes.fetch_add(packet.size(), std::memory_order_acq_rel);
                        pipe->incoming.push(std::move(packet));
                    }
                    received.erase(received.begin(), received.begin() + size + 2);
                    continue;
                }
            }
            if (read >= receiveBudget)
                break;
            std::array<std::uint8_t, 8192> buffer;
            const auto n =
                recv(pipe->handle, reinterpret_cast<char*>(buffer.data()), buffer.size(), 0);
            if (n == SOCKET_ERROR && blocked())
                break;
            if (n == 0) {
                if (!received.empty())
                    throw std::runtime_error("Truncated network frame");
                pipe->state.store(ConnectionPipe::closed, std::memory_order_release);
                return false;
            }
            if (n < 0)
                throw std::runtime_error("Peer receive failed");
            read += n;
            received.insert(received.end(), buffer.begin(), buffer.begin() + n);
        }
        pipe->receiveCapacity.store(received.capacity(), std::memory_order_release);
        pipe->world.cached.store(world.cachedBytes());
        pipe->world.flightBytes.store(world.inFlightBytes());
        pipe->world.flightStates.store(world.inFlightStates());
        pipe->world.worldBytes.store(world.worldBytes());
        pipe->world.oldestMs.store(world.oldestMs());
        pipe->world.snapshots.store(world.totals.snapshots);
        pipe->world.deltas.store(world.totals.deltas);
        pipe->world.raw.store(world.totals.raw);
        pipe->world.wire.store(world.totals.wire);
        pipe->world.full.store(world.totals.full);
        again = again ||
                (sending.outgoing.empty() &&
                 (!bulk.empty() || world.canSend(pipe->minimumLatency.load()))) ||
                (read >= receiveBudget && !pipe->incoming.full() &&
                 pipe->incomingBytes.load() < maxIncomingBytes);
        return true;
    }
};
struct NetworkIo::Listener {
    std::shared_ptr<ListenerPipe> pipe;
    WSAEVENT event = WSACreateEvent();
    explicit Listener(std::shared_ptr<ListenerPipe> value) : pipe(std::move(value)) {
        if (event == WSA_INVALID_EVENT || WSAEventSelect(pipe->handle, event, FD_ACCEPT | FD_CLOSE))
            pipe->failed.store(true, std::memory_order_release);
    }
    ~Listener() {
        // The main thread is the accepted queue's only consumer. Session
        // shutdown closes every connection, including unclaimed accepts.
        closesocket(pipe->handle);
        if (event != WSA_INVALID_EVENT)
            WSACloseEvent(event);
    }
};
NetworkIo::NetworkIo() {
    thread = CreateThread(nullptr, 0, run, this, 0, nullptr);
    if (!thread)
        throw std::runtime_error("Cannot start network worker");
}
NetworkIo::~NetworkIo() {
    stop();
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
    // Also cover attachment after a fatal worker failure was published.
    while (auto value = additions.pop())
        closesocket((*value)->handle);
    while (auto value = listeners.pop())
        closesocket((*value)->handle);
}
std::shared_ptr<ConnectionPipe> NetworkIo::attach(SOCKET socket,
                                                  std::optional<sockaddr_in> address) {
    auto pipe = std::make_shared<ConnectionPipe>(socket, address.has_value());
    pipe->address = address;
    auto queued = pipe;
    if (!additions.push(std::move(queued))) {
        closesocket(socket);
        throw std::runtime_error("Connection task queue limit exceeded");
    }
    wake.signal();
    return pipe;
}
std::shared_ptr<ListenerPipe> NetworkIo::listen(SOCKET socket) {
    auto pipe = std::make_shared<ListenerPipe>(socket);
    auto queued = pipe;
    if (!listeners.push(std::move(queued))) {
        closesocket(socket);
        throw std::runtime_error("Listener task queue limit exceeded");
    }
    wake.signal();
    return pipe;
}
DWORD WINAPI NetworkIo::run(void* argument) {
    auto& self = *static_cast<NetworkIo*>(argument);
    try {
        std::vector<std::unique_ptr<Connection>> connections;
        std::vector<std::unique_ptr<Listener>> listeners;
        StateCompression worldCodec, messageCodec(maxMessageSize);
        for (;;) {
            while (auto value = self.additions.pop())
                connections.push_back(std::make_unique<Connection>(std::move(*value)));
            while (auto value = self.listeners.pop())
                listeners.push_back(std::make_unique<Listener>(std::move(*value)));
            if (self.stopping.load(std::memory_order_acquire)) {
                for (const auto& value : listeners)
                    value->pipe->closing.store(true, std::memory_order_release);
                for (const auto& value : connections)
                    value->pipe->closing.store(true, std::memory_order_release);
            }
            for (auto it = listeners.begin(); it != listeners.end();) {
                auto& listener = **it;
                if (listener.pipe->closing.load(std::memory_order_acquire) ||
                    listener.pipe->failed.load()) {
                    it = listeners.erase(it);
                    continue;
                }
                WSANETWORKEVENTS events{};
                WSAEnumNetworkEvents(listener.pipe->handle, listener.event, &events);
                if (!listener.pipe->accepted.full()) {
                    const auto socket = accept(listener.pipe->handle, nullptr, nullptr);
                    if (socket != INVALID_SOCKET) {
                        auto pipe = std::make_shared<ConnectionPipe>(socket, false);
                        connections.push_back(std::make_unique<Connection>(pipe));
                        listener.pipe->accepted.push(std::move(pipe));
                    } else if (!blocked())
                        listener.pipe->failed.store(true, std::memory_order_release);
                }
                ++it;
            }
            for (auto it = connections.begin(); it != connections.end();) {
                bool alive = false;
                try {
                    alive = (*it)->service(messageCodec, worldCodec);
                } catch (const std::exception& error) {
                    (*it)->pipe->error = error.what();
                    (*it)->pipe->state.store(ConnectionPipe::failed, std::memory_order_release);
                }
                if (alive)
                    ++it;
                else
                    it = connections.erase(it);
            }
            if (self.stopping.load(std::memory_order_acquire) && connections.empty() &&
                listeners.empty())
                break;
            std::vector<HANDLE> handles{self.wake.handle()};
            for (const auto& connection : connections)
                if (connection->event != WSA_INVALID_EVENT)
                    handles.push_back(connection->event);
            for (const auto& listener : listeners)
                if (listener->event != WSA_INVALID_EVENT)
                    handles.push_back(listener->event);
            const bool again = std::any_of(connections.begin(), connections.end(),
                                           [](const auto& value) { return value->again; });
            if (WaitForMultipleObjects(handles.size(), handles.data(), FALSE, again ? 0 : 50) ==
                WAIT_FAILED)
                throw std::runtime_error("Network event wait failed");
        }
    } catch (const std::exception& error) {
        self.failure = error.what();
        self.failed.store(true, std::memory_order_release);
    }
    while (auto value = self.additions.pop())
        closesocket((*value)->handle);
    while (auto value = self.listeners.pop())
        closesocket((*value)->handle);
    return 0;
}
} // namespace isaac::lan

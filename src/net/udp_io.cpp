#include "net/network_io.h"
#include "net/message_receiver.h"
#include "net/messages.h"
#include "net/wire_codec.h"
#include <enet/enet.h>
#include <algorithm>
#include <map>

namespace isaac::lan {
namespace {
using Clock = std::chrono::steady_clock;
constexpr enet_uint8 reliableChannel = 0, inputChannel = 1, worldChannel = 2, recoveryChannel = 3;
constexpr std::size_t channelCount = 4, datagramMtu = 1200;
constexpr std::size_t maxDatagramMessage = maxWorldSize + 128;
constexpr auto closeGrace = std::chrono::seconds(2);
// This envelope is below the game protocol. A reliable fence invalidates
// in-flight state and input when the authority changes a run/floor generation.
enum class Envelope : std::uint8_t { message, world, fence };
struct PacketAccount {
    std::shared_ptr<ConnectionPipe> pipe;
    std::size_t bytes;
    std::shared_ptr<std::atomic<bool>> completed;
};
void ENET_CALLBACK releasePacket(ENetPacket* packet) {
    auto* account = static_cast<PacketAccount*>(packet->userData);
    if (account->pipe)
        account->pipe->queued.fetch_sub(account->bytes, std::memory_order_acq_rel);
    if (account->completed)
        account->completed->store(true, std::memory_order_release);
    delete account;
}
} // namespace

class DatagramHost {
  public:
    ENetHost* handle = nullptr;
    WSAEVENT event = WSA_INVALID_EVENT;
    explicit DatagramHost(std::optional<std::uint16_t> port) {
        if (enet_initialize())
            throw std::runtime_error("Cannot initialize UDP transport");
        ENetAddress address{ENET_HOST_ANY, port.value_or(0)};
        handle = enet_host_create(port ? &address : nullptr, maxPlayers + 1, channelCount, 0, 0);
        if (handle) {
            // Fragment below common tunnel/path MTUs; never rely on IP fragmentation.
            // ENet appends the checksum after its packet-size budget, including
            // packets that aggregate ACKs with data. Reserve those four bytes.
            handle->mtu = datagramMtu - sizeof(enet_uint32);
            handle->maximumPacketSize = maxDatagramMessage;
            handle->maximumWaitingData = 4 * maxWorldSize;
            handle->checksum = enet_crc32;
            event = WSACreateEvent();
        }
        if (!handle || event == WSA_INVALID_EVENT ||
            WSAEventSelect(handle->socket, event, FD_READ | FD_WRITE)) {
            if (handle)
                enet_host_destroy(handle);
            if (event != WSA_INVALID_EVENT)
                WSACloseEvent(event);
            enet_deinitialize();
            throw std::runtime_error("Cannot bind UDP transport");
        }
    }
    ~DatagramHost() {
        enet_host_destroy(handle);
        WSACloseEvent(event);
        enet_deinitialize();
    }
};

namespace {
struct DatagramConnection {
    ENetPeer* peer;
    std::shared_ptr<ConnectionPipe> pipe;
    bool authority;
    WorldGeneration generation{};
    std::uint32_t fence = 0;
    WorldTransfer world{true};
    ReliableReceiver reliable;
    struct Bulk {
        std::shared_ptr<const ReliableTransfer> transfer;
        std::size_t offset = 0;
        bool started = false;
    };
    std::deque<Bulk> bulk;
    std::optional<IncomingPacket> pending;
    std::optional<Clock::time_point> closingAt;
    std::shared_ptr<std::atomic<bool>> recoveryComplete = std::make_shared<std::atomic<bool>>(true);
    Clock::time_point recoveryAt{};
    std::size_t recoveryBytes = 0;
    DatagramConnection(ENetPeer* value, std::shared_ptr<ConnectionPipe> connection, bool host)
        : peer(value), pipe(std::move(connection)), authority(host) {
        enet_peer_timeout(peer, 8, 3000, 10000);
        enet_peer_ping_interval(peer, 250);
    }
    ~DatagramConnection() {
        // Releasing packets also releases their queue accounting.
        enet_peer_reset(peer);
    }
    bool capacity() const {
        return !pipe->incoming.full() && pipe->incomingBytes.load() < maxIncomingBytes;
    }
    void deliver(IncomingPacket packet) {
        if (!packet.size())
            return;
        if (!capacity()) {
            pending = std::move(packet);
            return;
        }
        pipe->incomingBytes.fetch_add(packet.size(), std::memory_order_acq_rel);
        pipe->incoming.push(std::move(packet));
    }
    void send(std::span<const std::uint8_t> bytes, enet_uint8 channel, Envelope kind,
              std::size_t accounted = 0) {
        Writer envelope(static_cast<Message>(kind));
        envelope.u32(fence);
        envelope.bytes.insert(envelope.bytes.end(), bytes.begin(), bytes.end());
        auto* packet = enet_packet_create(envelope.bytes.data(), envelope.bytes.size(),
                                          channel == reliableChannel || channel == recoveryChannel
                                              ? ENET_PACKET_FLAG_RELIABLE
                                              : ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT);
        if (!packet)
            throw std::runtime_error("Cannot allocate UDP packet");
        if (accounted || channel == recoveryChannel) {
            packet->userData =
                new PacketAccount{accounted ? pipe : nullptr, accounted,
                                  channel == recoveryChannel ? recoveryComplete : nullptr};
            packet->freeCallback = releasePacket;
        }
        if (enet_peer_send(peer, channel, packet)) {
            enet_packet_destroy(packet);
            throw std::runtime_error("UDP send failed");
        }
    }
    void message(std::vector<std::uint8_t> bytes, StateCompression& codec,
                 std::size_t accounted = 0) {
        const auto type = static_cast<Message>(bytes.at(0));
        const auto channel = type == Message::input ? inputChannel : reliableChannel;
        send(encodeWire(std::move(bytes), codec), channel, Envelope::message, accounted);
    }
    void synchronizeSender() {
        const auto requested = pipe->generation.load(std::memory_order_acquire);
        if (requested == generation)
            return;
        generation = requested;
        world.resetSender();
        world.epoch(generation.epoch);
        if (authority) {
            ++fence;
            send({}, reliableChannel, Envelope::fence);
        }
    }
    void receive(std::span<const std::uint8_t> packet, enet_uint8 channel, StateCompression& codec,
                 StateCompression& worldCodec) {
        Reader envelope(packet);
        const auto kind = static_cast<Envelope>(envelope.u8());
        const auto context = envelope.u32();
        if (kind == Envelope::fence) {
            envelope.finish();
            if (channel != reliableChannel || authority || context <= fence)
                throw std::runtime_error("Invalid UDP generation fence");
            fence = context;
            world.resetReceiver();
            return;
        }
        if (packet.size() <= 5)
            throw std::runtime_error("Empty UDP message");
        // A newer snapshot can overtake its reliable floor commit. Drop it;
        // the following publication recovers after the fence is delivered.
        if (channel != reliableChannel && context != fence)
            return;
        IncomingPacket incoming;
        if (kind == Envelope::world) {
            if ((channel != worldChannel && channel != recoveryChannel) || authority)
                throw std::runtime_error("Invalid UDP world channel");
            Reader r(packet.subspan(5));
            if (static_cast<Message>(r.u8()) != Message::world)
                throw std::runtime_error("Invalid UDP world message");
            incoming.world = world.receive(r, worldCodec);
            if (incoming.world)
                pipe->samples.push({"decompress", world.expandMs});
        } else if (kind == Envelope::message) {
            auto bytes = decodeWire(packet.subspan(5), codec);
            const auto type = static_cast<Message>(bytes.at(0));
            if ((type == Message::input) != (channel == inputChannel) ||
                (channel != inputChannel && channel != reliableChannel))
                throw std::runtime_error("Invalid UDP message channel");
            // Reliable one-shot input from an old generation must not leak
            // into the next floor/run even if it was waiting for retransmission.
            if (type == Message::inputEdges && context != fence)
                return;
            if (type == Message::world)
                throw std::runtime_error("Invalid UDP world envelope");
            incoming = receiveMessage(std::move(bytes), world, reliable, pipe->answerPing.load(),
                                      [&](Writer pong) { message(std::move(pong.bytes), codec); });
        } else
            throw std::runtime_error("Invalid UDP envelope");
        deliver(std::move(incoming));
    }
    void observe() {
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
        pipe->receiveCapacity.store(peer->totalWaitingData);
    }
    bool service(StateCompression& codec, StateCompression& worldCodec) {
        if (pending && capacity()) {
            deliver(std::move(*pending));
            pending.reset();
        }
        if (pipe->closing.load() && !closingAt)
            closingAt = Clock::now();
        if (pipe->state.load() == ConnectionPipe::connecting)
            return !closingAt;
        synchronizeSender();
        std::optional<std::vector<std::uint8_t>> input;
        while (auto packet = pipe->outgoing.pop()) {
            if (packet->transfer) {
                if (bulk.size() >= 4)
                    throw std::runtime_error("Reliable transaction queue limit exceeded");
                pipe->bulkBytes.fetch_add(packet->transfer->size());
                bulk.push_back({std::move(packet->transfer)});
                continue;
            }
            auto bytes = std::move(packet->bytes);
            const auto type = static_cast<Message>(bytes.at(0));
            const auto accounted = bytes.size() + 2;
            if (type == Message::input) {
                pipe->queued.fetch_sub(accounted);
                if (input)
                    pipe->coalescedInputs.fetch_add(1);
                input = std::move(bytes);
            } else {
                if (type == Message::ending || type == Message::finish || type == Message::error ||
                    type == Message::restart || type == Message::goodbye) {
                    bulk.clear();
                    pipe->bulkBytes.store(0);
                }
                message(std::move(bytes), codec, accounted);
            }
        }
        if (input)
            message(std::move(*input), codec);
        if (auto publication = pipe->publication.take()) {
            synchronizeSender();
            if (publication->generation == generation)
                world.publish(std::move(publication->value));
        }
        for (unsigned part = 0;
             !closingAt && !bulk.empty() && part < 8 && pipe->queued.load() < 16384; ++part) {
            auto& current = bulk.front();
            const auto sendBulk = [&](std::vector<std::uint8_t> bytes) {
                const auto accounted = bytes.size() + 2;
                pipe->queued.fetch_add(accounted);
                message(std::move(bytes), codec, accounted);
            };
            if (!current.started && !current.transfer->header.empty())
                sendBulk(current.transfer->header);
            current.started = true;
            sendBulk(current.transfer->chunk(current.offset).bytes);
            current.offset += std::min(bulkChunkSize, current.transfer->size() - current.offset);
            if (current.transfer->checkpoint)
                pipe->checkpointSent.store(current.offset);
            if (current.offset == current.transfer->size()) {
                pipe->bulkBytes.fetch_sub(current.transfer->size());
                bulk.pop_front();
            }
        }
        // A large reliable recovery may outlive the lossy flight records.
        // Reserve its byte budget until ENet finishes it; publishing another
        // large unreliable copy every expiry would compete with its retries.
        if (!closingAt && bulk.empty() &&
            (recoveryComplete->load() || recoveryBytes < WorldTransfer::maxInFlightBytes)) {
            if (auto state = world.next(worldCodec, pipe->minimumLatency.load())) {
                // One complete recovery view may be retried on its own channel.
                // Large initial views must eventually establish a baseline even
                // when no unreliable fragmented copy survives. Other channels
                // can deliver independently, but share bandwidth and ENet's
                // reliable window. Stale decodes never replace newer state.
                const bool recovery = !world.trace.delta && recoveryComplete->load() &&
                                      Clock::now() - recoveryAt >= std::chrono::milliseconds(500);
                if (recovery) {
                    recoveryComplete->store(false);
                    recoveryAt = Clock::now();
                    recoveryBytes = state->bytes.size();
                    world.retainRecovery();
                }
                send(state->bytes, recovery ? recoveryChannel : worldChannel, Envelope::world);
                pipe->samples.push({"compress", world.compressMs});
                pipe->samples.push({"delta.encode", world.prefixMs});
                if (world.trace.tick % 300 == 0)
                    pipe->traces.push(WorldTransfer::Trace(world.trace));
            }
        }
        observe();
        if (closingAt) {
            if (peer->state == ENET_PEER_STATE_CONNECTED)
                enet_peer_disconnect_later(peer, 0);
            if (Clock::now() - *closingAt >= closeGrace) {
                pipe->state.store(ConnectionPipe::closed, std::memory_order_release);
                return false;
            }
        }
        return peer->state != ENET_PEER_STATE_DISCONNECTED;
    }
};
} // namespace

std::shared_ptr<ConnectionPipe> NetworkIo::connectDatagram(const sockaddr_in& address) {
    auto pipe = std::make_shared<ConnectionPipe>(INVALID_SOCKET, true);
    pipe->unreliable = true;
    pipe->address = address;
    pipe->datagrams = std::make_shared<DatagramHost>(std::nullopt);
    auto queued = pipe;
    if (!additions.push(std::move(queued)))
        throw std::runtime_error("Connection task queue limit exceeded");
    wake.signal();
    return pipe;
}
std::shared_ptr<ListenerPipe> NetworkIo::listenDatagram(std::uint16_t port) {
    auto pipe = std::make_shared<ListenerPipe>(INVALID_SOCKET);
    pipe->datagrams = std::make_shared<DatagramHost>(port);
    pipe->port = pipe->datagrams->handle->address.port;
    auto queued = pipe;
    if (!listeners.push(std::move(queued)))
        throw std::runtime_error("Listener task queue limit exceeded");
    wake.signal();
    return pipe;
}
void NetworkIo::runDatagrams() {
    try {
        struct Endpoint {
            std::shared_ptr<DatagramHost> host;
            std::shared_ptr<ListenerPipe> listener;
            std::map<ENetPeer*, std::unique_ptr<DatagramConnection>> connections;
        };
        std::vector<Endpoint> endpoints;
        StateCompression worldCodec, messageCodec(maxMessageSize);
        for (;;) {
            while (auto value = listeners.pop())
                endpoints.push_back({(*value)->datagrams, *value, {}});
            while (auto value = additions.pop()) {
                auto pipe = *value;
                Endpoint endpoint{pipe->datagrams, {}, {}};
                ENetAddress address{pipe->address->sin_addr.s_addr, ntohs(pipe->address->sin_port)};
                auto* peer = enet_host_connect(endpoint.host->handle, &address, channelCount,
                                               protocolVersion);
                if (!peer)
                    throw std::runtime_error("Cannot connect UDP peer");
                endpoint.connections.emplace(
                    peer, std::make_unique<DatagramConnection>(peer, pipe, false));
                endpoints.push_back(std::move(endpoint));
            }
            for (auto endpoint = endpoints.begin(); endpoint != endpoints.end();) {
                auto& e = *endpoint;
                const bool closing = stopping.load() || (e.listener && e.listener->closing.load());
                WSANETWORKEVENTS events{};
                WSAEnumNetworkEvents(e.host->handle->socket, e.host->event, &events);
                for (auto it = e.connections.begin(); it != e.connections.end();) {
                    auto& connection = *it->second;
                    if (closing)
                        connection.pipe->closing.store(true);
                    bool alive = false;
                    try {
                        alive = connection.service(messageCodec, worldCodec);
                    } catch (const std::exception& error) {
                        connection.pipe->error = error.what();
                        connection.pipe->state.store(ConnectionPipe::failed,
                                                     std::memory_order_release);
                    }
                    if (!alive)
                        it = e.connections.erase(it);
                    else
                        ++it;
                }
                ENetEvent event{};
                for (unsigned count = 0; count < 256; ++count) {
                    const bool blocked = std::any_of(
                        e.connections.begin(), e.connections.end(),
                        [](const auto& pair) { return pair.second->pending.has_value(); });
                    if (blocked)
                        break;
                    const auto status = enet_host_service(e.host->handle, &event, 0);
                    if (status < 0)
                        throw std::runtime_error("UDP service failed");
                    if (!status)
                        break;
                    auto found = e.connections.find(event.peer);
                    if (event.type == ENET_EVENT_TYPE_CONNECT) {
                        // Configure only after the ENet handshake: this call
                        // queues a reliable command, not just local options.
                        // A short RTT window recovers promptly after path changes.
                        enet_peer_throttle_configure(event.peer, 500, 4, 2);
                        if (found == e.connections.end()) {
                            if (closing || !e.listener || e.listener->accepted.full() ||
                                event.data != protocolVersion) {
                                enet_peer_disconnect_now(event.peer, 0);
                                continue;
                            }
                            auto pipe = std::make_shared<ConnectionPipe>(INVALID_SOCKET, false);
                            pipe->unreliable = true;
                            e.connections.emplace(event.peer, std::make_unique<DatagramConnection>(
                                                                  event.peer, pipe, true));
                            e.listener->accepted.push(std::move(pipe));
                        } else
                            found->second->pipe->state.store(ConnectionPipe::connected,
                                                             std::memory_order_release);
                    } else if (event.type == ENET_EVENT_TYPE_DISCONNECT) {
                        if (found != e.connections.end()) {
                            found->second->pipe->state.store(ConnectionPipe::closed,
                                                             std::memory_order_release);
                            e.connections.erase(found);
                        }
                    } else if (event.type == ENET_EVENT_TYPE_RECEIVE) {
                        if (found != e.connections.end()) {
                            try {
                                found->second->receive(
                                    {event.packet->data, event.packet->dataLength}, event.channelID,
                                    messageCodec, worldCodec);
                            } catch (const std::exception& error) {
                                found->second->pipe->error = error.what();
                                found->second->pipe->state.store(ConnectionPipe::failed,
                                                                 std::memory_order_release);
                                e.connections.erase(found);
                            }
                        }
                        enet_packet_destroy(event.packet);
                    }
                }
                enet_host_flush(e.host->handle);
                if (e.connections.empty() && (closing || !e.listener))
                    endpoint = endpoints.erase(endpoint);
                else
                    ++endpoint;
            }
            if (stopping.load() && endpoints.empty())
                break;
            std::vector<HANDLE> handles{wake.handle()};
            for (const auto& e : endpoints)
                handles.push_back(e.host->event);
            // ENet timers need service even without socket readiness. Main-thread
            // publication/input wakes this wait immediately.
            if (WaitForMultipleObjects(handles.size(), handles.data(), FALSE, 5) == WAIT_FAILED)
                throw std::runtime_error("UDP event wait failed");
        }
    } catch (const std::exception& error) {
        failure = error.what();
        failed.store(true, std::memory_order_release);
    }
}
} // namespace isaac::lan

#include "net/network_io.h"
#include "net/datagram_protocol.h"
#include "net/message_receiver.h"
#include "net/messages.h"
#include "net/wire_codec.h"
#include "net/world_dependencies.h"
#include "net/world_shards.h"
#include <enet/enet.h>
#include <algorithm>
#include <map>

namespace isaac::lan {
namespace {
using Clock = std::chrono::steady_clock;
using namespace datagram;
constexpr std::size_t maxDatagramMessage = maxWorldSize + 128;
constexpr auto closeGrace = std::chrono::seconds(2);
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
            handle->mtu = mtu - sizeof(enet_uint32);
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
    WorldTransfer world;
    WorldDependencies dependencies;
    WorldShards shards;
    std::deque<std::vector<std::uint8_t>> outgoingShards;
    std::size_t outgoingShardBytes = 0;
    std::optional<WorldState> publication;
    std::vector<std::uint8_t> currentDependency, sentDependency, receivedDependency;
    std::uint32_t dependencyRevision = 0, sentDependencyRevision = 0,
                  receivedDependencyRevision = 0;
    std::size_t dependencyBytes = 0;
    std::uint64_t dependencyRaw = 0, dependencyWire = 0, dependencyFull = 0, redundancyWire = 0;
    std::shared_ptr<std::atomic<bool>> dependencyComplete =
        std::make_shared<std::atomic<bool>>(true);
    ReliableReceiver reliable;
    struct Bulk {
        std::shared_ptr<const ReliableTransfer> transfer;
        std::size_t offset = 0;
        bool started = false;
    };
    std::deque<Bulk> bulk;
    std::optional<IncomingPacket> pending;
    std::optional<std::vector<std::uint8_t>> latestReceipt;
    Clock::time_point receiptAt{};
    std::optional<Clock::time_point> closingAt;
    std::shared_ptr<std::atomic<bool>> recoveryComplete = std::make_shared<std::atomic<bool>>(true);
    Clock::time_point recoveryAt{};
    DatagramConnection(ENetPeer* value, std::shared_ptr<ConnectionPipe> connection, bool host)
        : peer(value), pipe(std::move(connection)), authority(host) {
        // Keep ENet's default retry budget for reliable checkpoints on slow
        // links. Session input/loading deadlines still own game liveness.
        enet_peer_timeout(peer, ENET_PEER_TIMEOUT_LIMIT, ENET_PEER_TIMEOUT_MINIMUM,
                          ENET_PEER_TIMEOUT_MAXIMUM);
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
              std::size_t accounted = 0, std::shared_ptr<std::atomic<bool>> completed = nullptr,
              bool unordered = false) {
        Writer envelope(static_cast<Message>(kind));
        envelope.u32(fence);
        envelope.bytes.insert(envelope.bytes.end(), bytes.begin(), bytes.end());
        auto* packet = enet_packet_create(
            envelope.bytes.data(), envelope.bytes.size(),
            channel == reliableChannel || channel == recoveryChannel ? ENET_PACKET_FLAG_RELIABLE
            : kind == Envelope::shard || unordered                   ? ENET_PACKET_FLAG_UNSEQUENCED
                                                   : ENET_PACKET_FLAG_UNRELIABLE_FRAGMENT);
        if (!packet)
            throw std::runtime_error("Cannot allocate UDP packet");
        if (accounted || completed || channel == recoveryChannel) {
            packet->userData =
                new PacketAccount{accounted ? pipe : nullptr, accounted,
                                  channel == recoveryChannel ? recoveryComplete : completed};
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
        const auto channel =
            type == Message::input || type == Message::applied ? inputChannel : reliableChannel;
        // Receipts and held inputs advance independently. Sharing ENet's
        // unreliable sequence would let a newer input discard a delayed
        // receipt (or vice versa). Receipts are cumulative and already checked
        // against the generation and acknowledged world tick.
        send(encodeWire(std::move(bytes), codec), channel, Envelope::message, accounted, nullptr,
             type == Message::applied);
    }
    void synchronizeSender() {
        const auto requested = pipe->generation.load(std::memory_order_acquire);
        if (requested == generation)
            return;
        generation = requested;
        world.resetSender();
        world.epoch(generation.epoch);
        publication.reset();
        latestReceipt.reset();
        outgoingShards.clear();
        outgoingShardBytes = 0;
        currentDependency.clear();
        sentDependency.clear();
        dependencyRevision = sentDependencyRevision = 0;
        dependencyBytes = 0;
        dependencyComplete = std::make_shared<std::atomic<bool>>(true);
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
            dependencies.reset();
            receivedDependency.clear();
            receivedDependencyRevision = 0;
            shards.reset();
            latestReceipt.reset();
            return;
        }
        if (packet.size() <= 5)
            throw std::runtime_error("Empty UDP message");
        // A newer snapshot can overtake its reliable floor commit. Drop it;
        // the following publication recovers after the fence is delivered.
        if (channel != reliableChannel && context != fence)
            return;
        IncomingPacket incoming;
        if (kind == Envelope::world || kind == Envelope::shard) {
            if ((channel != worldChannel && channel != recoveryChannel) || authority)
                throw std::runtime_error("Invalid UDP world channel");
            std::optional<std::vector<std::uint8_t>> restored;
            auto payload = packet.subspan(5);
            if (kind == Envelope::shard) {
                if (channel != worldChannel)
                    throw std::runtime_error("Invalid UDP shard channel");
                restored = shards.receive(payload);
                if (!restored)
                    return;
                payload = *restored;
            }
            Reader r(payload);
            if (static_cast<Message>(r.u8()) != Message::world)
                throw std::runtime_error("Invalid UDP world message");
            incoming.world = world.receive(r, worldCodec);
            if (incoming.world) {
                pipe->samples.push({"decompress", world.expandMs});
                incoming.world = dependencies.receive(std::move(*incoming.world));
            }
        } else if (kind == Envelope::dependency) {
            if (channel != reliableChannel || authority || context != fence)
                throw std::runtime_error("Invalid UDP dependency channel");
            Reader r(packet.subspan(5));
            const auto revision = r.u32();
            const auto bytes = r.blob(maxWorldSize + StateCompression::headerSize);
            r.finish();
            if (revision <= receivedDependencyRevision)
                throw std::runtime_error("Invalid reliable dependency revision");
            // The reliable prefix chain is independent of inline copies that
            // can overtake it. Coalescing may skip intermediate revisions.
            receivedDependency = worldCodec.expand(bytes, receivedDependency);
            receivedDependencyRevision = revision;
            incoming.world = dependencies.receive(revision, receivedDependency);
        } else if (kind == Envelope::message) {
            auto bytes = decodeWire(packet.subspan(5), codec);
            const auto type = static_cast<Message>(bytes.at(0));
            const bool realtime = type == Message::input || type == Message::applied;
            if (realtime != (channel == inputChannel) ||
                (channel != inputChannel && channel != reliableChannel))
                throw std::runtime_error("Invalid UDP message channel");
            // Reliable one-shot input from an old generation must not leak
            // into the next floor/run even if it was waiting for retransmission.
            if ((type == Message::inputEdges || type == Message::applied) && context != fence)
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
        pipe->world.cached.store(world.cachedBytes() + dependencies.cachedBytes() +
                                 currentDependency.capacity() + sentDependency.capacity() +
                                 receivedDependency.capacity() + shards.buffered());
        pipe->world.flightBytes.store(world.inFlightBytes());
        pipe->world.flightStates.store(world.inFlightStates());
        pipe->world.worldBytes.store(world.worldBytes() + outgoingShardBytes);
        pipe->world.oldestMs.store(world.oldestMs());
        pipe->world.snapshots.store(world.totals.snapshots);
        pipe->world.deltas.store(world.totals.deltas);
        pipe->world.raw.store(world.totals.raw + dependencyRaw);
        pipe->world.wire.store(world.totals.wire + dependencyWire + redundancyWire);
        pipe->world.full.store(world.totals.full + dependencyFull);
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
        bool receiptChanged = false;
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
            const auto accounted = bytes.size();
            if (type == Message::applied) {
                pipe->queued.fetch_sub(accounted);
                latestReceipt = std::move(bytes);
                receiptChanged = true;
            } else if (type == Message::input) {
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
        // A receipt is cumulative latest-state feedback, not a transaction.
        // Ordered retransmission here would stall the UDP publication window
        // behind an old missing ACK. Repeat the newest receipt so a lost final
        // ACK also recovers without waiting for a new view.
        constexpr auto receiptInterval = std::chrono::milliseconds(100);
        if (!closingAt && latestReceipt &&
            (receiptChanged || Clock::now() - receiptAt >= receiptInterval)) {
            message(*latestReceipt, codec);
            receiptAt = Clock::now();
        }
        if (auto latest = pipe->publication.take()) {
            synchronizeSender();
            if (latest->generation == generation)
                publication = std::move(latest->value);
        }
        if (!closingAt && publication && bulk.empty()) {
            auto& value = *publication;
            if (!value.stable.empty()) {
                if (value.stable != currentDependency) {
                    if (++dependencyRevision == 0)
                        throw std::runtime_error("World dependency revision exhausted");
                    currentDependency = value.stable;
                }
                value.revision = dependencyRevision;
                // Bootstrap once through reliable delivery. Thereafter each
                // unacknowledged revision is self-contained in newer views;
                // loss of the ordered copy cannot freeze realtime state.
                if (!world.hasBaseline() || world.acknowledgedRevision() == dependencyRevision)
                    value.stable.clear();
            }
            world.publish(std::move(value));
            publication.reset();
        }
        if (!closingAt && bulk.empty() && dependencyComplete->load() &&
            sentDependencyRevision != dependencyRevision) {
            Writer dependency(Message::world);
            dependency.u32(dependencyRevision);
            dependencyFull += worldCodec.compress(currentDependency).size();
            dependency.blob(worldCodec.compress(currentDependency, sentDependency));
            sentDependency = currentDependency;
            sentDependencyRevision = dependencyRevision;
            dependencyRaw += sentDependency.size();
            dependencyWire += dependency.bytes.size() - 1;
            dependencyBytes = dependency.bytes.size() + 1;
            pipe->queued.fetch_add(dependencyBytes);
            dependencyComplete->store(false);
            // Same reliable channel as the fence; at most one pending copy.
            send(std::span(dependency.bytes).subspan(1), reliableChannel, Envelope::dependency,
                 dependencyBytes, dependencyComplete);
        }
        for (unsigned part = 0;
             !closingAt && !bulk.empty() && part < 8 && pipe->queued.load() < 16384; ++part) {
            auto& current = bulk.front();
            const auto sendBulk = [&](std::vector<std::uint8_t> bytes) {
                const auto accounted = bytes.size();
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
        // At most one reliable full recovery is retained until ENet finishes it.
        // Once a baseline exists, the independently bounded realtime window must
        // keep progressing even if that old recovery is still being retried.
        // Otherwise one large recovery can head-of-line block every newer view.
        // Removing the last bulk chunk from our deque only means it entered
        // ENet. Its accounted bytes remain until acknowledged; let that tail
        // drain before realtime traffic competes for the same path again.
        const auto queued = pipe->queued.load();
        const auto dependencyQueued = dependencyComplete->load() ? 0 : dependencyBytes;
        if (!closingAt && bulk.empty() && outgoingShards.empty() &&
            queued - std::min(queued, dependencyQueued) < bulkChunkSize &&
            // Without an application receipt every view is a full copy.
            // Bootstrap one reliable candidate and wait for its receipt, or
            // retry after the recovery interval if it crossed a generation fence.
            (world.hasBaseline() || (recoveryComplete->load() &&
                                     Clock::now() - recoveryAt >= WorldTransfer::lostStateAge))) {
            if (auto state = world.next(worldCodec, pipe->minimumLatency.load())) {
                // One complete recovery view may be retried on its own channel.
                // Large initial views must eventually establish a baseline even
                // when no unreliable fragmented copy survives. Other channels
                // can deliver independently, but share bandwidth and ENet's
                // reliable window. Stale decodes never replace newer state.
                const bool recovery = !world.trace.delta && recoveryComplete->load() &&
                                      Clock::now() - recoveryAt >= WorldTransfer::lostStateAge;
                if (recovery) {
                    recoveryComplete->store(false);
                    recoveryAt = Clock::now();
                    world.retainRecovery();
                }
                // ENet's unreliable fragments are sequenced: a newer view can
                // retire an incomplete older view before its delayed fragment
                // arrives. Use independent shards for every fragmented view,
                // including the common two/three-datagram deltas. Match ENet's
                // fragmentation budget, including our generation envelope.
                constexpr auto envelopeHeader = sizeof(std::uint8_t) + sizeof(std::uint32_t);
                const auto fragmentLimit =
                    peer->mtu - sizeof(ENetProtocolHeader) - sizeof(ENetProtocolSendFragment) -
                    (peer->host->checksum ? sizeof(enet_uint32) : 0) - envelopeHeader;
                const auto shardCount = WorldShards::packetCount(state->bytes.size());
                if (!recovery && state->bytes.size() > fragmentLimit &&
                    shardCount <= ENET_PEER_UNSEQUENCED_WINDOW_SIZE) {
                    // ENet discards the previous 1024-sequence window as soon
                    // as a newer one arrives. A view must fit within one window;
                    // otherwise ordinary packet reordering can erase its first
                    // groups before the last groups finish.
                    const auto remaining =
                        std::size_t(ENET_PEER_UNSEQUENCED_WINDOW_SIZE) -
                        peer->outgoingUnsequencedGroup % ENET_PEER_UNSEQUENCED_WINDOW_SIZE;
                    if (shardCount >= remaining)
                        peer->outgoingUnsequencedGroup = static_cast<enet_uint16>(
                            peer->outgoingUnsequencedGroup + remaining - 1);
                    std::size_t emitted = 0;
                    WorldShards::send(world.trace.tick, state->bytes,
                                      [&](std::span<const std::uint8_t> shard) {
                                          emitted += shard.size();
                                          outgoingShards.emplace_back(shard.begin(), shard.end());
                                          outgoingShardBytes += shard.size();
                                      });
                    redundancyWire += emitted - state->bytes.size();
                } else
                    send(state->bytes, recovery ? recoveryChannel : worldChannel, Envelope::world);
                pipe->samples.push({"compress", world.compressMs});
                pipe->samples.push({"delta.encode", world.prefixMs});
                if (world.trace.tick % 300 == 0)
                    pipe->traces.push(WorldTransfer::Trace(world.trace));
            }
        }
        // Bound each burst as well as total in-flight views. Large FEC frames
        // must not overflow a receiver's socket queue before its next poll.
        constexpr unsigned shardsPerService = 16;
        for (unsigned part = 0;
             !closingAt && bulk.empty() && !outgoingShards.empty() && part < shardsPerService;
             ++part) {
            auto& shard = outgoingShards.front();
            send(shard, worldChannel, Envelope::shard);
            outgoingShardBytes -= shard.size();
            outgoingShards.pop_front();
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
    auto pipe = std::make_shared<ConnectionPipe>(true);
    pipe->address = address;
    pipe->datagrams = std::make_shared<DatagramHost>(std::nullopt);
    auto queued = pipe;
    if (!additions.push(std::move(queued)))
        throw std::runtime_error("Connection task queue limit exceeded");
    wake.signal();
    return pipe;
}
std::shared_ptr<ListenerPipe> NetworkIo::listenDatagram(std::uint16_t port) {
    auto pipe = std::make_shared<ListenerPipe>();
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
                        // ENet's packet throttle can drop the entire queued
                        // unsequenced shard group when a single packet loses
                        // its lottery. Pace complete views in WorldTransfer;
                        // never randomly discard their parity/data locally.
                        // This call queues a command, so it follows the handshake.
                        enet_peer_throttle_configure(event.peer, 500, 4, 0);
                        if (found == e.connections.end()) {
                            if (closing || !e.listener || e.listener->accepted.full() ||
                                event.data != protocolVersion) {
                                enet_peer_disconnect_now(event.peer, 0);
                                continue;
                            }
                            auto pipe = std::make_shared<ConnectionPipe>(false);
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

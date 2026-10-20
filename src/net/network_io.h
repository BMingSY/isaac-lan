#pragma once
#include "net/byte_worker.h"
#include "net/protocol.h"
#include "core/latest_mailbox.h"
#include "net/reliable_transfer.h"
#include "net/reliable_receiver.h"
#include "net/world_transfer.h"
#include "net/transport.h"
#include <deque>

namespace isaac::lan {
class DatagramHost;
inline constexpr std::size_t maxSocketQueueBytes = 262144;
inline constexpr std::size_t maxIncomingBytes = 2 * maxWorldSize;
struct IncomingPacket {
    std::vector<std::uint8_t> bytes;
    std::optional<WorldState> world;
    std::optional<ReceivedBulk> bulk;
    std::size_t size() const {
        return bytes.size() + (world ? world->bytes.size() + world->stable.size() : 0) +
               (bulk ? bulk->size() : 0);
    }
};
struct OutgoingPacket {
    std::vector<std::uint8_t> bytes;
    std::shared_ptr<const ReliableTransfer> transfer;
};
struct WorldGeneration {
    std::uint32_t revision = 0, epoch = 0;
    bool operator==(const WorldGeneration&) const = default;
};
struct WorldPublication {
    WorldGeneration generation;
    WorldState value;
};
struct NetworkSample {
    const char* name;
    double milliseconds;
};
struct WorldObservation {
    std::atomic<std::size_t> cached{0}, flightBytes{0}, flightStates{0}, worldBytes{0};
    std::atomic<std::uint64_t> oldestMs{0}, snapshots{0}, deltas{0}, raw{0}, wire{0}, full{0};
};
// Main-thread producer / network-thread consumer for outgoing, reversed for
// incoming. Socket state and queue counters are observations, never ownership.
struct ConnectionPipe {
    enum State { connecting, connected, closed, failed };
    SOCKET handle;
    bool unreliable = false;
    std::shared_ptr<DatagramHost> datagrams;
    std::optional<sockaddr_in> address;
    SpscQueue<OutgoingPacket, 128> outgoing;
    SpscQueue<IncomingPacket, 128> incoming;
    SpscQueue<NetworkSample, 64> samples;
    SpscQueue<WorldTransfer::Trace, 8> traces;
    LatestMailbox<WorldPublication> publication;
    std::atomic<WorldGeneration> generation{};
    std::atomic<std::uint64_t> coalescedInputs{0};
    std::atomic<int> minimumLatency{-1};
    WorldObservation world;
    std::atomic<State> state;
    std::atomic<bool> closing{false}, answerPing{false};
    std::atomic<std::size_t> queued{0}, receiveCapacity{0}, incomingBytes{0};
    std::atomic<std::size_t> checkpointSent{0}, bulkBytes{0};
    std::string error; // Written once, published by terminal state release.
    explicit ConnectionPipe(SOCKET socket, bool pending)
        : handle(socket), state(pending ? connecting : connected) {}
};
struct ListenerPipe {
    SOCKET handle;
    std::shared_ptr<DatagramHost> datagrams;
    std::uint16_t port = 0;
    SpscQueue<std::shared_ptr<ConnectionPipe>, 4> accepted;
    std::atomic<bool> closing{false}, failed{false};
    explicit ListenerPipe(SOCKET socket) : handle(socket) {}
};
// One event-driven owner for established sockets and realtime byte processing.
// Bind/listen/nonblocking-connect are setup operations before ownership transfer.
class NetworkIo {
    struct Connection;
    struct Listener;
    WakeEvent wake;
    SpscQueue<std::shared_ptr<ConnectionPipe>, 8> additions;
    SpscQueue<std::shared_ptr<ListenerPipe>, 2> listeners;
    std::atomic<bool> stopping{false};
    std::atomic<bool> failed{false};
    std::string failure;
    HANDLE thread = nullptr;
    static DWORD WINAPI run(void* self);
    void runDatagrams();
    Transport transport;

  public:
    explicit NetworkIo(Transport mode = Transport::tcp);
    ~NetworkIo();
    NetworkIo(const NetworkIo&) = delete;
    void stop() {
        stopping.store(true, std::memory_order_release);
        wake.signal();
    }
    bool finished() const {
        return WaitForSingleObject(thread, 0) == WAIT_OBJECT_0;
    }
    void check() const {
        if (failed.load(std::memory_order_acquire))
            throw std::runtime_error(failure);
    }
    std::shared_ptr<ConnectionPipe> attach(SOCKET socket, std::optional<sockaddr_in> address = {});
    std::shared_ptr<ListenerPipe> listen(SOCKET socket);
    std::shared_ptr<ConnectionPipe> connectDatagram(const sockaddr_in& address);
    std::shared_ptr<ListenerPipe> listenDatagram(std::uint16_t port);
    void signal() {
        wake.signal();
    }
};
} // namespace isaac::lan

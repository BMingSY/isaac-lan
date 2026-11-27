#include "net/steam_transport.h"
#include "net/datagram_protocol.h"
#include "net/protocol.h"
#include <isteamnetworkingsockets.h>
#include <isteamnetworkingutils.h>
#include <chrono>
#include <map>
#include <mutex>
#include <sstream>

namespace isaac::lan::steam {
namespace {
using Clock = std::chrono::steady_clock;
constexpr size_t maxRequests = 16;
constexpr auto admissionGrace = std::chrono::seconds(2);
struct Request {
    HSteamNetConnection connection;
    Clock::time_point at;
};
struct ListenerEvents final : Callback {
    ISteamNetworkingSockets& sockets;
    std::mutex mutex;
    HSteamListenSocket listener{};
    std::vector<Request> requests;
    explicit ListenerEvents(ISteamNetworkingSockets& api)
        : Callback(SteamNetConnectionStatusChangedCallback_t::k_iCallback), sockets(api) {}
    int size() override {
        return sizeof(SteamNetConnectionStatusChangedCallback_t);
    }
    void event(void* data) override {
        const auto& update = *static_cast<SteamNetConnectionStatusChangedCallback_t*>(data);
        if (update.m_info.m_eState != k_ESteamNetworkingConnectionState_Connecting ||
            !update.m_info.m_hListenSocket)
            return;
        std::lock_guard lock(mutex);
        if (listener != update.m_info.m_hListenSocket)
            return;
        if (requests.size() == maxRequests)
            sockets.CloseConnection(update.m_hConn, k_ESteamNetConnectionEnd_App_Generic, nullptr,
                                    false);
        else
            requests.push_back({update.m_hConn, Clock::now()});
    }
};
class SocketRoute final : public Transport {
    Api& api;
    ISteamNetworkingSockets& sockets;
    const Id self, host;
    Logger logger;
    std::optional<ESteamNetworkingConnectionState> lastClientState;
    HSteamListenSocket listener{};
    HSteamNetPollGroup group{};
    ListenerEvents inbox;
    std::mutex mutex;
    std::map<Id, HSteamNetConnection> peers;
    std::vector<Request> requests;
    Clock::time_point nextCheck{};
    bool live(HSteamNetConnection connection, SteamNetConnectionInfo_t& info) {
        if (!sockets.GetConnectionInfo(connection, &info)) {
            info = {};
            return false;
        }
        return info.m_eState >= k_ESteamNetworkingConnectionState_Connecting &&
               info.m_eState <= k_ESteamNetworkingConnectionState_Connected;
    }
    void peerEvent(const char* event, HSteamNetConnection handle,
                   const SteamNetConnectionInfo_t& info) const {
        if (logger)
            logger(std::string("steam_p2p=") + event + " link=" + std::to_string(handle) +
                   " state=" + std::to_string(info.m_eState) +
                   " end_reason=" + std::to_string(info.m_eEndReason));
    }
    bool clientLive(HSteamNetConnection handle, SteamNetConnectionInfo_t& info) {
        const bool active = live(handle, info);
        if (lastClientState != info.m_eState) {
            lastClientState = info.m_eState;
            peerEvent("client_state", handle, info);
        }
        return active;
    }
    void close(HSteamNetConnection h) {
        sockets.CloseConnection(h, k_ESteamNetConnectionEnd_App_Generic, nullptr, false);
    }

  public:
    SocketRoute(Api& platform, Id owner, Logger log)
        : api(platform), sockets(*platform.sockets), self(platform.local), host(owner), logger(log),
          inbox(sockets) {}
    bool start() {
        api.networkingUtils->InitRelayNetworkAccess();
        group = sockets.CreatePollGroup();
        if (!group)
            return false;
        if (self == host) {
            listener = sockets.CreateListenSocketP2P(virtualPort, 0, nullptr);
            if (!listener)
                return false;
            inbox.listener = listener;
            api.subscribe(&inbox, inbox.callback);
            return true;
        }
        SteamNetworkingIdentity identity{};
        identity.SetSteamID64(host);
        auto h = sockets.ConnectP2P(identity, virtualPort, 0, nullptr);
        if (!h)
            return false;
        peers.emplace(host, h);
        return sockets.SetConnectionPollGroup(h, group);
    }
    void stopListening() {
        std::lock_guard guard(mutex);
        if (listener) {
            api.unsubscribe(&inbox);
            {
                std::lock_guard lock(inbox.mutex);
                if (inbox.listener == listener) {
                    inbox.listener = 0;
                    inbox.requests.clear();
                }
            }
            sockets.CloseListenSocket(listener);
            listener = 0;
            peers.clear();
            requests.clear();
        }
    }
    ~SocketRoute() override {
        if (!api.alive())
            return;
        stopListening();
        for (auto [id, h] : peers)
            close(h);
        if (group)
            sockets.DestroyPollGroup(group);
    }
    Id localAccount() const override {
        return self;
    }
    Id hostAccount() const override {
        return host;
    }
    State state() override {
        std::lock_guard guard(mutex);
        if (self == host)
            return listener ? State::connected : State::closed;
        SteamNetConnectionInfo_t info{};
        auto peer = peers.find(host);
        if (peer == peers.end() || !clientLive(peer->second, info))
            return State::closed;
        return info.m_eState == k_ESteamNetworkingConnectionState_Connected ? State::connected
                                                                            : State::connecting;
    }
    std::shared_ptr<DatagramRoute> reconnect() override {
        if (self == host)
            return {};
        {
            std::lock_guard guard(mutex);
            if (auto old = peers.find(host); old != peers.end()) {
                close(old->second);
                peers.erase(old);
            }
        }
        return open(api, host, logger);
    }
    void service(const std::function<bool(Id)>& allowed) override {
        std::lock_guard guard(mutex);
        if (!listener)
            return;
        {
            std::lock_guard lock(inbox.mutex);
            requests.insert(requests.end(), inbox.requests.begin(), inbox.requests.end());
            inbox.requests.clear();
        }
        const auto now = Clock::now();
        if (requests.empty() && now < nextCheck)
            return;
        nextCheck = now + std::chrono::milliseconds(250);
        SteamNetConnectionInfo_t info{};
        std::erase_if(peers, [&](const auto& peer) {
            if (live(peer.second, info))
                return false;
            peerEvent("closed", peer.second, info);
            close(peer.second);
            return true;
        });
        std::erase_if(requests, [&](const Request& r) {
            if (!live(r.connection, info) || info.m_hListenSocket != listener) {
                close(r.connection);
                return true;
            }
            const Id remote = info.m_identityRemote.GetSteamID64();
            if (remote && !peers.contains(remote) && peers.size() < maxPlayers - 1 &&
                allowed(remote)) {
                if (sockets.AcceptConnection(r.connection) == k_EResultOK &&
                    sockets.SetConnectionPollGroup(r.connection, group)) {
                    peers.emplace(remote, r.connection);
                    peerEvent("admitted", r.connection, info);
                    return true;
                }
            } else if (remote && now - r.at < admissionGrace && requests.size() <= maxRequests)
                return false;
            peerEvent("rejected", r.connection, info);
            close(r.connection);
            return true;
        });
    }
    int send(Id destination, std::span<const std::uint8_t> bytes) override {
        std::lock_guard guard(mutex);
        auto peer = peers.find(destination);
        if (peer == peers.end())
            return 0;
        auto result =
            sockets.SendMessageToConnection(peer->second, bytes.data(), bytes.size(),
                                            k_nSteamNetworkingSend_UnreliableNoDelay, nullptr);
        // ENet owns retransmission and channel ordering. Local congestion, discovery
        // and an already disconnected guest have the same semantics as a UDP drop.
        return result == k_EResultOK ? static_cast<int>(bytes.size()) : 0;
    }
    int receive(Id& source, std::span<std::uint8_t> bytes) override {
        std::lock_guard guard(mutex);
        if (self != host && Clock::now() >= nextCheck) {
            nextCheck = Clock::now() + std::chrono::milliseconds(250);
            SteamNetConnectionInfo_t info{};
            if (!peers.contains(host) || !clientLive(peers.at(host), info))
                return -1;
        }
        SteamNetworkingMessage_t* message = nullptr;
        int count = sockets.ReceiveMessagesOnPollGroup(group, &message, 1);
        if (count <= 0)
            return count;
        source = message->m_identityPeer.GetSteamID64();
        auto peer = peers.find(source);
        int size = message->m_cbSize;
        if (!source || peer == peers.end() || peer->second != message->m_conn || size <= 0 ||
            static_cast<size_t>(size) > std::min<size_t>(bytes.size(), datagram::mtu))
            size = -2;
        else
            std::memcpy(bytes.data(), message->m_pData, size);
        message->Release();
        return size;
    }
    std::string diagnostics() override {
        std::lock_guard guard(mutex);
        std::ostringstream out;
        for (auto [id, h] : peers) {
            SteamNetConnectionInfo_t info{};
            SteamNetConnectionRealTimeStatus_t status{};
            if (!live(h, info) || info.m_eState != k_ESteamNetworkingConnectionState_Connected ||
                sockets.GetConnectionRealTimeStatus(h, &status, 0, nullptr) != k_EResultOK)
                continue;
            char pop[5]{};
            GetSteamNetworkingLocationPOPStringFromID(info.m_idPOPRelay, pop);
            out << " steam_route="
                << (info.m_idPOPRelay                                              ? "SDR"
                    : (info.m_nFlags & k_nSteamNetworkConnectionInfoFlags_Relayed) ? "relay"
                                                                                   : "direct")
                << " pop=" << (info.m_idPOPRelay ? pop : "-") << " rtt_ms=" << status.m_nPing
                << " max_jitter_us=" << status.m_usecMaxJitter
                << " delivery_quality=" << status.m_flConnectionQualityLocal << " link=" << h;
        }
        return out.str();
    }
};
} // namespace
std::shared_ptr<Transport> Transport::open(Api& api, Id host, Logger logger) {
    if (!host || !api.local)
        return {};
    auto route = std::make_shared<SocketRoute>(api, host, logger);
    return route->start() ? route : nullptr;
}
} // namespace isaac::lan::steam

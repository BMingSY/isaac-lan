#include "net/session.h"
#include "net/side_channel.h"
#include "net/messages.h"
#include "net/peer.h"
#include "net/host_resolution.h"
#include "net/compression.h"
#include "net/host_address.h"
#include <winsock2.h>
#include <ws2tcpip.h>
#include <bcrypt.h>
#include <algorithm>
#include <chrono>
#include <deque>
#include <map>
#include <atomic>

namespace isaac::lan {
namespace {
using Clock = std::chrono::steady_clock;
std::string randomIdentity() {
    std::array<unsigned char, 16> bytes{};
    if (BCryptGenRandom(nullptr, bytes.data(), bytes.size(), BCRYPT_USE_SYSTEM_PREFERRED_RNG) < 0)
        throw std::runtime_error("Cannot create player identity");
    std::string result;
    for (auto value : bytes) {
        result.push_back("0123456789abcdef"[value >> 4]);
        result.push_back("0123456789abcdef"[value & 15]);
    }
    return result;
}
bool validIdentity(const std::string& value) {
    return value.size() == 32 && std::all_of(value.begin(), value.end(), [](char c) {
               return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
           });
}
} // namespace
struct Session::Impl {
    Observer observer = nullptr;
    bool debugLogs = false;
    Transport transport;
    std::shared_ptr<NetworkIo> io;
    std::unique_ptr<BulkWorker> bulk;
    std::shared_ptr<ByteResult<Stage>> encodingStage, decodingStage;
    std::shared_ptr<ByteResult<std::vector<std::uint8_t>>> decodingCheckpoint;
    BulkWorker& bulkWorker() {
        if (!bulk)
            bulk = std::make_unique<BulkWorker>();
        return *bulk;
    }
    void (*logger)(const std::string&);
    bool winsock = false, hosting = false, connecting = false, localReady = false,
         initialStarted = false;
    Phase state = Phase::idle;
    std::string failure, fingerprint, identity, mods, hostIP;
    std::shared_ptr<HostResolution> resolving;
    std::vector<sockaddr_in> hostAddresses;
    std::size_t nextHostAddress = 0;
    Clock::time_point joinAt;
    bool modMismatch = false, lobbyDirty = false, choicesRequired = false;
    std::array<std::string, maxPlayers> identities;
    LobbyAccess localAccess;
    std::array<LobbyAccess, maxPlayers> access;
    unsigned localSlot = 0, playerCount = 1, activeMask = 1;
    std::uint16_t boundPort = 0;
    std::shared_ptr<ListenerPipe> listener;
    std::array<std::unique_ptr<Peer>, maxPlayers> peers;
    std::vector<std::unique_ptr<Peer>> incoming;
    Start startSettings;
    RunRules runRules;
    std::uint32_t rulesRevision = 0;
    std::array<Choice, maxPlayers> choices{};
    std::array<Command, maxPlayers> commands{};
    std::array<InputFrame, maxPlayers> latest{};
    std::array<std::optional<InputRoom>, maxPlayers> inputRooms{};
    std::array<std::uint32_t, maxPlayers> sequences{};
    std::array<int, maxPlayers> latency{0, -1, -1, -1};
    Clock::time_point latencyAt = Clock::now() - std::chrono::seconds(1);
    std::uint32_t nextInput = 0, nextConsume = 0, committed = 0;
    std::optional<std::uint32_t> consumedLocal, verified;
    std::optional<WorldState> receivedState;
    std::optional<Stage> receivedStage;
    std::optional<std::uint32_t> cinematicEpoch;
    unsigned cinematicReadyMask = 0;
    std::optional<unsigned> ending;
    bool endingCompleted = false;
    std::optional<Ending> receivedEnding;
    std::array<std::optional<RoomRequest>, maxPlayers> roomRequests{};
    std::string integrationRun;
    std::uint32_t integrationEpoch = 0;
    SideChannel integration, communication, lifecycle;
    bool restartPending = false;
    unsigned returnedMask = 0;
    std::size_t snapshotSize = 0;
    std::uint32_t takenWorldEpoch = 0;
    std::uint64_t worldSnapshots = 0, deltaSnapshots = 0, rawWorldBytes = 0, wireWorldBytes = 0,
                  fullWorldBytes = 0;
    std::uint64_t snapshotChecksum = 0;
    Clock::time_point progress = Clock::now(), checkpointAt = Clock::now();

    explicit Impl(void (*log)(const std::string&), Observer observe = nullptr, bool debug = false,
                  Transport mode = Transport::udp)
        : observer(observe), debugLogs(debug), transport(mode), logger(log) {
        WSADATA data{};
        winsock = WSAStartup(MAKEWORD(2, 2), &data) == 0;
        if (winsock) {
            try {
                io = std::make_shared<NetworkIo>(transport);
            } catch (...) {
                WSACleanup();
                throw;
            }
        }
    }
    ~Impl() {
        shutdown();
        bulk.reset();
        io.reset();
        if (winsock)
            WSACleanup();
    }
    void shutdown() {
        encodingStage.reset();
        decodingStage.reset();
        decodingCheckpoint.reset();
        // A DNS worker owns its result and its own Winsock reference. Closing
        // a session never waits for DNS or lets that worker touch a new one.
        resolving.reset();
        hostAddresses.clear();
        if (listener) {
            listener->closing.store(true, std::memory_order_release);
            listener.reset();
            io->signal();
        }
        for (auto& peer : peers)
            retirePeer(peer);
        incoming.clear();
        integration = {};
        communication = {};
        lifecycle = {};
        if (bulk)
            bulk->stop();
        if (io)
            io->stop();
    }
    bool workersFinished() const {
        return (!io || io->finished()) && (!bulk || bulk->finished());
    }
    void retirePeer(std::unique_ptr<Peer>& peer) {
        if (peer && peer->pipe) {
            const auto& totals = peer->pipe->world;
            worldSnapshots += totals.snapshots.load();
            deltaSnapshots += totals.deltas.load();
            rawWorldBytes += totals.raw.load();
            wireWorldBytes += totals.wire.load();
            fullWorldBytes += totals.full.load();
        }
        peer.reset();
    }
    void resetRun() {
        encodingStage.reset();
        decodingStage.reset();
        decodingCheckpoint.reset();
        returnedMask = 0;
        restartPending = false;
        localReady = initialStarted = false;
        nextInput = nextConsume = committed = 0;
        consumedLocal.reset();
        verified.reset();
        latest = {};
        inputRooms = {};
        sequences = {};
        commands = {};
        roomRequests = {};
        receivedState.reset();
        receivedStage.reset();
        cinematicEpoch.reset();
        cinematicReadyMask = 0;
        ending.reset();
        endingCompleted = false;
        receivedEnding.reset();
        integration = {};
        communication = {};
        lifecycle = {};
        takenWorldEpoch = integrationEpoch;
        for (auto& p : peers)
            if (p) {
                p->ready = p->hasInput = false;
                p->inputSequence = 0;
                p->edgeSequence.reset();
                p->inputEdges.clear();
                p->acknowledged.reset();
                p->resetWorldCache(integrationEpoch);
                p->sendingStage.reset();
                p->floorAfterLoad.reset();
                p->checkpoint.reset();
                p->preparingCheckpoint.reset();
                p->loadingAt = Clock::now();
            }
        progress = Clock::now();
    }
    void connectNextAddress() {
        peers[0].reset();
        while (nextHostAddress < hostAddresses.size()) {
            const auto& address = hostAddresses[nextHostAddress++];
            if (transport == Transport::udp) {
                peers[0] = std::make_unique<Peer>(io, io->connectDatagram(address));
                connecting = true;
                return;
            }
            Socket setup(socket(AF_INET, SOCK_STREAM, IPPROTO_TCP));
            if (setup.handle == INVALID_SOCKET)
                throw std::runtime_error("Cannot create LAN socket");
            configure(setup.handle);
            peers[0] = std::make_unique<Peer>(
                io, io->attach(std::exchange(setup.handle, INVALID_SOCKET), address));
            connecting = true;
            return;
        }
        throw std::runtime_error("Cannot connect to host");
    }
    void fail(const std::string& reason) {
        if (state == Phase::failed)
            return;
        failure = reason;
        state = Phase::failed;
        if (logger)
            logger("network_failure=" + reason);
        Writer w(Message::error);
        w.string(reason.substr(0, 240));
        for (auto& p : peers)
            if (p) {
                try {
                    p->sendMessage(w);
                    p->flush();
                } catch (...) {
                }
            }
        shutdown();
    }
    void broadcast(const Writer& w) {
        for (auto& p : peers)
            if (p && p->accepted)
                p->sendMessage(w);
    }
    bool sendSideChannel(Message type, SideChannel& channel, std::size_t limit,
                         unsigned destination, const std::string& bytes) {
        const bool chat = type == Message::communication;
        if (destination >= playerCount || bytes.empty() || bytes.size() > limit ||
            (state != Phase::lobby && state != Phase::running &&
             !(chat && state == Phase::waiting)))
            return false;
        if (hosting && !destination)
            return channel.enqueue(0, bytes);
        if (!hosting && destination)
            return false;
        auto& peer = peers[hosting ? destination : 0];
        constexpr std::size_t maxSideChannelBacklog = 32768;
        if (!peer || !peer->accepted || peer->queuedBytes() > maxSideChannelBacklog)
            return false;
        Writer w(type);
        w.blob({reinterpret_cast<const std::uint8_t*>(bytes.data()), bytes.size()});
        peer->sendMessage(w);
        return true;
    }
    void measureLatency() {
        if (!hosting)
            return;
        const auto now = Clock::now();
        for (unsigned slot = 1; slot < maxPlayers; ++slot)
            if (auto& peer = peers[slot]; peer && peer->accepted) {
                if (now - peer->pingAt < std::chrono::seconds(peer->pingPending ? 5 : 1) ||
                    peer->queuedBytes() > 16384)
                    continue;
                Writer ping(Message::ping);
                ping.u32(++peer->pingSequence);
                peer->sendMessage(ping);
                peer->pingAt = now;
                peer->pingPending = true;
            } else
                latency[slot] = -1;
        if (now - latencyAt < std::chrono::seconds(1))
            return;
        latencyAt = now;
        Writer info(Message::latency);
        for (auto ms : latency)
            info.u16(ms < 0 ? 65535 : std::min(ms, 65534));
        broadcast(info);
    }
    void updateMods(bool force = false) {
        const bool different = std::any_of(peers.begin(), peers.end(), [&](const auto& p) {
            return p && p->accepted && (mods.empty() || p->mods.empty() || p->mods != mods);
        });
        if (!force && different == modMismatch)
            return;
        modMismatch = different;
        Writer w(Message::modStatus);
        w.u8(different);
        broadcast(w);
    }
    bool rulesAvailable(const RunRules& rules, bool continuing = false) const {
        if (!localAccess.allowsRules(rules, continuing))
            return false;
        if (hosting) {
            for (unsigned i = 1; i < maxPlayers; ++i)
                if (peers[i] && peers[i]->accepted && !access[i].allowsRules(rules, continuing))
                    return false;
        } else {
            for (unsigned i = 0; i < playerCount; ++i)
                if (!access[i].allowsRules(rules, continuing))
                    return false;
        }
        return true;
    }
    void lobby() {
        unsigned next = 1;
        for (unsigned i = 1; i < maxPlayers; ++i)
            if (peers[i] && peers[i]->accepted) {
                if (i != next) {
                    std::swap(peers[i], peers[next]);
                    std::swap(choices[i], choices[next]);
                    std::swap(identities[i], identities[next]);
                    std::swap(access[i], access[next]);
                }
                ++next;
            }
        playerCount = next;
        activeMask = (1u << playerCount) - 1;
        for (unsigned i = 0; i < playerCount; ++i) {
            auto& choice = choices[i];
            if (runRules.character != 65535)
                choice.character = runRules.character;
            else if (!access[i].allowsCharacter(choice.character) && !access[i].characters.empty())
                choice.character = access[i].characters.front();
        }
        const bool allowed = rulesAvailable(runRules);
        for (unsigned i = 0; i < playerCount; ++i)
            if (!allowed || !access[i].allowsCharacter(choices[i].character))
                choices[i].ready = false;
        for (unsigned i = 1; i < playerCount; ++i) {
            Writer w(Message::lobby);
            w.u8(playerCount);
            w.u8(i);
            w.u32(rulesRevision);
            writeRules(w, runRules);
            for (auto choice : choices) {
                w.u16(choice.character);
                w.u8(choice.ready);
            }
            for (const auto& value : access)
                w.access(value);
            peers[i]->sendMessage(w);
        }
        lobbyDirty = false;
        updateMods(true);
    }
    void finishReturn() {
        if (!hosting || state != Phase::returning || (returnedMask & activeMask) != activeMask)
            return;
        // A disconnected/rejoining seat has no completed local run. It is not
        // part of this barrier or the next lobby's compact, connected roster.
        for (unsigned slot = 1; slot < maxPlayers; ++slot)
            if (peers[slot] && !(activeMask & (1u << slot))) {
                Writer finish(Message::finish);
                finish.u32(committed);
                try {
                    peers[slot]->sendMessage(finish);
                    peers[slot]->flush();
                } catch (...) {
                }
                remove(slot);
            }
        incoming.clear();
        resetRun();
        for (unsigned slot = 1; slot < maxPlayers; ++slot)
            if (!peers[slot]) {
                identities[slot].clear();
                access[slot] = {};
                choices[slot] = {};
            }
        ++rulesRevision;
        choicesRequired = true;
        for (auto& choice : choices)
            choice.ready = false;
        for (auto& peer : peers)
            if (peer)
                peer->loadingAt.reset();
        state = Phase::lobby;
        lobbyDirty = true;
        if (logger)
            logger("network_return=LOBBY");
    }
    Writer startMessage(Message type, const Start& value, std::size_t size = 0,
                        std::uint64_t checksum = snapshotHash({})) {
        Writer w(type);
        writeRules(w, value.rules);
        w.string(value.seed);
        w.u8(value.difficulty);
        for (auto c : value.characters)
            w.u16(c);
        w.progress(value.progress);
        w.string(integrationRun);
        w.u32(integrationEpoch);
        w.u32(value.firstTick);
        w.u8(value.connected);
        w.u32(size);
        w.u64(checksum);
        return w;
    }
    void finishCinematic() {
        if (!hosting || !cinematicEpoch || (cinematicReadyMask & activeMask) != activeMask)
            return;
        Writer release(Message::cinematic);
        release.u32(*cinematicEpoch);
        release.u8(2);
        broadcast(release);
        cinematicEpoch.reset();
        progress = Clock::now();
        for (auto& p : peers)
            if (p)
                p->inputAt = Clock::now();
    }
    void remove(unsigned slot) {
        activeMask &= ~(1u << slot);
        latest[slot] = {};
        inputRooms[slot].reset();
        commands[slot] = Command::none;
        roomRequests[slot].reset();
        retirePeer(peers[slot]);
        for (auto* channel : {&integration, &communication, &lifecycle})
            std::erase_if(channel->queue,
                          [slot](const auto& message) { return message.sender == slot; });
        if (state == Phase::lobby) {
            choices[slot] = {};
            identities[slot].clear();
            access[slot] = {};
            lobbyDirty = true;
        }
        if (logger)
            logger("network_departure slot=" + std::to_string(slot));
    }
    void acceptHello(unsigned slot, Reader& r) {
        if (r.u16() != protocolVersion || r.string() != fingerprint)
            throw std::runtime_error("Game, extension or protocol mismatch");
        const auto id = r.string();
        auto& p = *peers[slot];
        p.mods = r.string();
        const auto declaredAccess = r.access();
        if (!validIdentity(id) ||
            std::find(identities.begin(), identities.end(), id) != identities.end())
            throw std::runtime_error("Invalid or duplicate player identity");
        identities[slot] = id;
        access[slot] = declaredAccess;
        p.accepted = true;
        if (!rulesAvailable(runRules)) {
            for (auto& choice : choices)
                choice.ready = false;
            ++rulesRevision;
        }
        Writer welcome(Message::welcome);
        welcome.u8(slot);
        p.sendMessage(welcome);
        lobbyDirty = true;
    }
    void message(unsigned slot, Reader& r) {
        const auto type = static_cast<Message>(r.u8());
        auto& p = *peers[slot];
        if ((type == Message::integration || type == Message::communication ||
             type == Message::lifecycle) &&
            p.accepted) {
            const bool chat = type == Message::communication;
            auto bytes = r.blob(chat ? maxCommunicationSize : maxIntegrationSize);
            r.finish();
            if (bytes.empty() || (state != Phase::lobby && state != Phase::running &&
                                  !(chat && state == Phase::waiting)))
                return;
            if (!chat && hosting && state == Phase::running &&
                (!p.ready || p.waiting || p.rejoining))
                return;
            (chat                         ? communication
             : type == Message::lifecycle ? lifecycle
                                          : integration)
                .receive(hosting ? slot : 0, {bytes.begin(), bytes.end()});
            return;
        }
        if (type == Message::ping && !hosting && p.accepted) {
            Writer response(Message::pong);
            response.u32(r.u32());
            p.sendMessage(response);
            return;
        }
        if (type == Message::pong && hosting && p.accepted) {
            const auto sequence = r.u32();
            if (p.pingPending && sequence == p.pingSequence) {
                latency[slot] = static_cast<int>(std::min<std::int64_t>(
                    65534,
                    std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - p.pingAt)
                        .count()));
                p.pingPending = false;
                if (p.minimumLatency < 0 || latency[slot] < p.minimumLatency)
                    p.minimumLatency = latency[slot];
                p.pipe->minimumLatency.store(p.minimumLatency);
            }
            return;
        }
        if (type == Message::latency && !hosting && p.accepted) {
            for (auto& ms : latency) {
                const auto value = r.u16();
                ms = value == 65535 ? -1 : value;
            }
            return;
        }
        if (type == Message::error)
            throw std::runtime_error("Peer: " + r.string());
        if (type == Message::goodbye)
            throw ConnectionLost("Peer left the session");
        if (hosting) {
            if (!p.accepted && type == Message::hello && state == Phase::lobby) {
                acceptHello(slot, r);
                return;
            }
            if (!p.accepted)
                throw std::runtime_error("Handshake required");
            if (type == Message::returnLobby) {
                const auto run = r.string();
                if (run == integrationRun && ending && *ending != ending::gameOver &&
                    (state == Phase::running || state == Phase::returning))
                    returnedMask |= 1u << slot;
                return;
            }
            if (type == Message::cinematic && state == Phase::running) {
                const auto epoch = r.u32();
                if (!cinematicEpoch || epoch != *cinematicEpoch || r.u8() != 1 ||
                    !(activeMask & (1u << slot)))
                    throw std::runtime_error("Invalid cinematic readiness");
                cinematicReadyMask |= 1u << slot;
                finishCinematic();
                return;
            }
            if (type == Message::choice && state == Phase::lobby) {
                const auto revision = r.u32();
                const auto c = r.u16(), ready = static_cast<std::uint16_t>(r.u8());
                if (ready > 1)
                    throw std::runtime_error("Invalid ready flag");
                if (revision != rulesRevision)
                    return; // Choice from the previous lobby rules.
                if (runRules.character != 65535 && c != runRules.character)
                    return;
                if (!access[slot].allowsCharacter(c) || (ready && !rulesAvailable(runRules)))
                    return;
                choices[slot] = {c, ready != 0};
                choicesRequired = true;
                lobbyDirty = true;
                return;
            }
            if (type == Message::loaded && p.checkpoint) {
                if (p.loaded ||
                    p.pipe->checkpointSent.load(std::memory_order_acquire) !=
                        p.checkpoint->wire.size() ||
                    r.u64() != p.checkpoint->checksum)
                    throw std::runtime_error("Invalid checkpoint receipt");
                p.loaded = true;
                p.advancedAt = Clock::now();
                return;
            }
            if (type == Message::ready && state == Phase::running) {
                const auto run = r.string();
                const auto epoch = r.u32();
                if (run != integrationRun)
                    return;
                if (epoch != (p.checkpoint ? p.checkpoint->settings.firstTick
                                           : startSettings.firstTick) ||
                    (p.checkpoint && !p.loaded))
                    throw std::runtime_error("Invalid engine readiness");
                p.ready = true;
                p.loadingAt.reset();
                p.checkpoint.reset();
                p.inputAt = Clock::now();
                p.hasInput = false;
                p.inputSequence = 0;
                p.edgeSequence.reset();
                p.inputEdges.clear();
                latest[slot] = {};
                inputRooms[slot].reset();
                // A slow loader may have an older floor checkpoint. Deliver
                // the latest native floor event before its first live view.
                if (p.floorAfterLoad) {
                    p.beginStage(*p.floorAfterLoad);
                    p.floorAfterLoad.reset();
                }
                if (p.rejoining) {
                    activeMask |= 1u << slot;
                    p.rejoining = false;
                    p.waiting = false;
                }
                return;
            }
            if ((type == Message::input || type == Message::inputEdges) &&
                (state == Phase::running || state == Phase::finishing ||
                 state == Phase::returning)) {
                const auto sample = readInput(r);
                const auto sequence = sample.sequence;
                const auto& value = sample.input;
                const auto& room = sample.room;
                if (!p.ready || p.waiting || state != Phase::running)
                    return;
                if (type == Message::inputEdges) {
                    if (transport != Transport::udp)
                        throw std::runtime_error("Unexpected input event transport");
                    if (p.edgeSequence && sequence <= *p.edgeSequence)
                        return;
                    p.edgeSequence = sequence;
                    if (p.inputEdges.size() >= 128)
                        throw std::runtime_error("Input event queue limit exceeded");
                    p.inputEdges.push_back(sample);
                    return;
                }
                if (p.hasInput && sequence <= p.inputSequence) {
                    if (transport == Transport::udp)
                        return;
                    throw std::runtime_error("Duplicate input sequence");
                }
                if (transport == Transport::udp && value.triggered)
                    throw std::runtime_error("Unreliable input contains one-shot actions");
                p.hasInput = true;
                p.inputSequence = sequence;
                p.inputAt = Clock::now();
                const auto edges = retainedInputEdges(latest[slot], inputRooms[slot], room);
                latest[slot] = value;
                latest[slot].triggered |= edges;
                inputRooms[slot] = room;
                sequences[slot] = sequence;
                return;
            }
            if (type == Message::control &&
                (state == Phase::running || state == Phase::returning)) {
                const auto c = r.u8();
                if (!c || c > static_cast<unsigned>(Command::leave) ||
                    c == static_cast<unsigned>(Command::saveExit))
                    throw std::runtime_error("Unauthorized shared command");
                if (p.ready && state == Phase::running)
                    commands[slot] = static_cast<Command>(c);
                return;
            }
            if (type == Message::roomRequest &&
                (state == Phase::running || state == Phase::returning)) {
                RoomRequest value;
                value.stage = r.u8();
                value.type = r.u8();
                value.sourceDimension = r.u8();
                value.dimension = r.u8();
                value.source = static_cast<std::int16_t>(r.u16());
                value.destination = static_cast<std::int16_t>(r.u16());
                const auto teleport = r.u8();
                if (value.stage < 1 || value.stage > 13 || value.type > 5 ||
                    value.sourceDimension > 2 || value.dimension > 2 || value.source < -20 ||
                    value.source >= 169 || value.destination < -20 || value.destination >= 169 ||
                    teleport > 1)
                    throw std::runtime_error("Invalid room command");
                value.teleport = teleport != 0;
                if (p.ready && !p.waiting && !p.rejoining && state == Phase::running)
                    roomRequests[slot] = value;
                return;
            }
            if (type == Message::applied && (state == Phase::running || state == Phase::finishing ||
                                             state == Phase::returning)) {
                const auto epoch = r.u32();
                const auto tick = r.u32();
                if (state == Phase::returning)
                    return;
                // A receipt sent before a reliable floor boundary may arrive
                // after its caches were retired. It cannot establish a new base.
                if (epoch < integrationEpoch)
                    return;
                if (epoch != integrationEpoch)
                    throw std::runtime_error("Invalid state receipt epoch");
                if (tick >= nextConsume || (p.acknowledged && tick <= *p.acknowledged))
                    throw std::runtime_error("Invalid state receipt");
                p.acknowledged = tick;
                p.advancedAt = Clock::now();
                return;
            }
            throw std::runtime_error("Unexpected client message");
        }
        if (type == Message::welcome && state == Phase::connecting) {
            localSlot = r.u8();
            if (!localSlot || localSlot >= maxPlayers)
                throw std::runtime_error("Invalid assigned slot");
            p.accepted = true;
            p.pipe->answerPing.store(true);
            state = Phase::lobby;
            return;
        }
        if (!p.accepted)
            throw std::runtime_error("Handshake required");
        if (type == Message::modStatus) {
            const auto n = r.u8();
            if (n > 1)
                throw std::runtime_error("Invalid Mod advisory");
            modMismatch = n != 0;
            return;
        }
        if (type == Message::finish) {
            r.u32();
            p.finished = true;
            state = Phase::closed;
            return;
        }
        if (type == Message::cinematic && state == Phase::running) {
            const auto epoch = r.u32();
            if (!cinematicEpoch || epoch != *cinematicEpoch || r.u8() != 2 ||
                !(cinematicReadyMask & (1u << localSlot)))
                throw std::runtime_error("Invalid cinematic release");
            cinematicEpoch.reset();
            progress = Clock::now();
            return;
        }
        if (type == Message::ending && state == Phase::running) {
            const auto value = r.u8();
            const auto completed = r.u8();
            if (value < ending::gameOver || value > ending::lastCinematic || ending ||
                completed > 1 || (completed && (!runRules.id || value == ending::gameOver)))
                throw std::runtime_error("Invalid authoritative ending");
            const auto progress = r.progress();
            if (!progress)
                throw std::runtime_error("Missing ending progression");
            ending = value;
            endingCompleted = completed != 0;
            receivedEnding = Ending{value, *progress, endingCompleted};
            receivedState.reset();
            receivedStage.reset();
            return;
        }
        if (type == Message::lobby && (state == Phase::lobby || state == Phase::returning)) {
            if (state == Phase::returning) {
                resetRun();
                p.loadingAt.reset();
                state = Phase::lobby;
            }
            playerCount = r.u8();
            localSlot = r.u8();
            rulesRevision = r.u32();
            runRules = readRules(r);
            if (playerCount < 2 || playerCount > maxPlayers || !localSlot ||
                localSlot >= playerCount)
                throw std::runtime_error("Invalid lobby");
            for (auto& c : choices) {
                c.character = r.u16();
                const auto n = r.u8();
                if (n > 1)
                    throw std::runtime_error("Invalid ready flag");
                c.ready = n != 0;
            }
            for (auto& value : access)
                value = r.access();
            if (access[localSlot] != localAccess)
                throw std::runtime_error("Lobby changed local profile access");
            activeMask = (1u << playerCount) - 1;
            return;
        }
        if (type == Message::waitFloor) {
            playerCount = r.u8();
            for (auto& character : startSettings.characters)
                character = r.u16();
            failure = r.string();
            if (playerCount < 2 || playerCount > 4 || localSlot >= playerCount)
                throw std::runtime_error("Invalid waiting roster");
            state = Phase::waiting;
            localReady = false;
            receivedState.reset();
            return;
        }
        if ((type == Message::start && (state == Phase::lobby || state == Phase::waiting)) ||
            (type == Message::restart && state == Phase::running)) {
            const bool restarting = type == Message::restart;
            const auto previousEpoch = integrationEpoch;
            auto envelope = readStart(r);
            auto value = std::move(envelope.settings);
            integrationRun = std::move(envelope.run);
            integrationEpoch = envelope.epoch;
            if (restarting && integrationEpoch <= previousEpoch)
                throw std::runtime_error("Invalid new run epoch");
            integration.queue.clear();
            snapshotSize = envelope.size;
            snapshotChecksum = envelope.checksum;
            if (value.seed.size() != 8 || value.difficulty > 3 || !(value.connected & 1) ||
                value.connected >= (1u << playerCount) ||
                snapshotSize > maxSnapshotSize + StateCompression::headerSize)
                throw std::runtime_error("Invalid start state");
            if (!localAccess.allowsRules(value.rules, snapshotSize != 0) ||
                !localAccess.allowsCharacter(value.characters[localSlot], snapshotSize != 0) ||
                (value.rules.character != 65535 &&
                 value.characters[localSlot] != value.rules.character) ||
                (value.rules.difficulty != 255 && value.difficulty != value.rules.difficulty))
                throw std::runtime_error("Start is unavailable for the local profile");
            if (restarting) {
                if (snapshotSize || value.firstTick || value.rules != runRules ||
                    value.characters != startSettings.characters ||
                    value.difficulty != startSettings.difficulty)
                    throw std::runtime_error("Invalid new run settings");
                resetRun();
                restartPending = true;
            }
            localReady = false;
            receivedState.reset();
            startSettings = value;
            runRules = value.rules;
            activeMask = value.connected;
            nextConsume = value.firstTick;
            nextInput = 0;
            state = snapshotSize ? Phase::loading : Phase::running;
            checkpointAt = Clock::now();
            progress = Clock::now();
            return;
        }
        throw std::runtime_error("Unexpected host message");
    }
    void receiveBulk(ReceivedBulk value) {
        if (hosting)
            throw std::runtime_error("Unexpected client bulk transfer");
        receivedState.reset();
        progress = Clock::now();
        if (value.stage) {
            if (state != Phase::running || !localReady)
                throw std::runtime_error("Unexpected floor transfer");
            peers[0]->resetWorldCache();
            if (value.stage->rewind.empty())
                receiveStage(std::move(*value.stage));
            else
                decodingStage = bulkWorker().submit(
                    [stage = std::move(*value.stage)](StateCompression& codec) mutable {
                        stage.rewind = codec.expand(stage.rewind);
                        return stage;
                    });
        } else {
            if (state != Phase::loading || value.checkpoint.size() != snapshotSize ||
                decodingCheckpoint)
                throw std::runtime_error("Unexpected checkpoint transfer");
            decodingCheckpoint =
                restoreCheckpoint(bulkWorker(), std::move(value.checkpoint), snapshotChecksum);
        }
    }
    void receiveStage(Stage value) {
        integrationEpoch = value.epoch;
        if (value.cinematic) {
            if (cinematicEpoch)
                throw std::runtime_error("Overlapping cinematic transaction");
            cinematicEpoch = value.epoch;
            cinematicReadyMask = 0;
        }
        receivedStage = std::move(value);
    }
    void sendStage(const Stage& encoded) {
        const auto data = std::make_shared<const Stage>(encoded);
        for (unsigned slot = 1; slot < playerCount; ++slot)
            if (auto& p = peers[slot]; p && p->accepted) {
                if (p->rejoining) {
                    p->floorAfterLoad = encoded;
                    continue;
                }
                if (p->ready && !p->waiting)
                    p->sendingStage = data;
            }
    }
    void finishBytes() {
        io->check();
        if (bulk)
            bulk->check();
        if (decodingCheckpoint && decodingCheckpoint->ready()) {
            startSettings.snapshot = decodingCheckpoint->take();
            if (logger)
                logger("checkpoint_received wire=" + std::to_string(snapshotSize) +
                       " raw=" + std::to_string(startSettings.snapshot.size()) + " restore_ms=" +
                       std::to_string(decodingCheckpoint->milliseconds) + " transfer_restore_ms=" +
                       std::to_string(
                           std::chrono::duration<double, std::milli>(Clock::now() - checkpointAt)
                               .count()));
            decodingCheckpoint.reset();
            Writer loaded(Message::loaded);
            loaded.u64(snapshotChecksum);
            peers[0]->sendMessage(loaded);
            state = Phase::running;
            progress = Clock::now();
        }
        if (decodingStage && decodingStage->ready()) {
            receiveStage(decodingStage->take());
            decodingStage.reset();
        }
        if (encodingStage && encodingStage->ready()) {
            sendStage(encodingStage->take());
            encodingStage.reset();
        }
    }
    void sendPending() {
        if (!hosting)
            return;
        for (unsigned slot = 1; slot < playerCount; ++slot)
            if (peers[slot]) {
                auto& p = *peers[slot];
                if (p.preparingCheckpoint) {
                    if (!p.preparingCheckpoint->ready())
                        continue;
                    // One immutable compressed result is shared by all recipients.
                    if (p.preparingCheckpoint->error)
                        std::rethrow_exception(p.preparingCheckpoint->error);
                    p.checkpoint = p.preparingCheckpoint->value.value();
                    if (logger)
                        logger("checkpoint_pack slot=" + std::to_string(slot) +
                               " raw=" + std::to_string(p.checkpoint->rawSize) +
                               " wire=" + std::to_string(p.checkpoint->wire.size()) +
                               " ms=" + std::to_string(p.preparingCheckpoint->milliseconds));
                    p.preparingCheckpoint.reset();
                }
                if (p.checkpoint && !p.loaded) {
                    if (!p.checkpointQueued) {
                        auto transfer = std::make_shared<ReliableTransfer>();
                        transfer->checkpoint = p.checkpoint;
                        transfer->header =
                            startMessage(Message::start, p.checkpoint->settings,
                                         p.checkpoint->wire.size(), p.checkpoint->checksum)
                                .bytes;
                        p.checkpointQueued = p.sendTransfer(std::move(transfer));
                    }
                    continue;
                }
                if (!p.ready)
                    continue;
                if (p.sendingStage) {
                    auto transfer = std::make_shared<ReliableTransfer>();
                    transfer->stage = p.sendingStage;
                    if (!p.sendTransfer(std::move(transfer)))
                        continue;
                    p.sendingStage.reset();
                }
                if (p.pending && !encodingStage) {
                    p.pending->epoch = integrationEpoch;
                    p.flush();
                    if (!p.outgoing.empty())
                        continue;
                    p.pipe->publication.publish(std::make_unique<WorldPublication>(
                        WorldPublication{p.pipe->generation.load(), std::move(*p.pending)}));
                    p.pending.reset();
                    io->signal();
                }
            }
    }
    void receiveReturning() {
        for (auto it = incoming.begin(); it != incoming.end();) {
            auto& p = **it;
            std::optional<unsigned> slot;
            std::optional<LobbyAccess> returnedAccess;
            bool rejected = false;
            try {
                if (Clock::now() - p.connectedAt > std::chrono::seconds(10))
                    throw std::runtime_error("Handshake timed out");
                p.receive([&](Reader& r) {
                    if (slot || r.u8() != static_cast<unsigned>(Message::hello) ||
                        r.u16() != protocolVersion || r.string() != fingerprint)
                        throw std::runtime_error("Game, extension or protocol mismatch");
                    const auto id = r.string();
                    p.mods = r.string();
                    const auto declaredAccess = r.access();
                    const auto found =
                        std::find(identities.begin() + 1, identities.begin() + playerCount, id);
                    if (!validIdentity(id) || found == identities.begin() + playerCount)
                        throw std::runtime_error("Only original players can rejoin");
                    const auto i = static_cast<unsigned>(found - identities.begin());
                    if (peers[i] || (activeMask & (1u << i)))
                        throw std::runtime_error("Player already connected");
                    if (!declaredAccess.allowsRules(runRules, true) ||
                        !declaredAccess.allowsCharacter(startSettings.characters[i], true))
                        throw std::runtime_error("Saved seat is unavailable for the local profile");
                    returnedAccess = declaredAccess;
                    slot = i;
                });
            } catch (const std::exception& e) {
                try {
                    Writer w(Message::error);
                    w.string(std::string(e.what()).substr(0, 240));
                    p.sendMessage(w);
                    p.flush();
                } catch (...) {
                }
                rejected = true;
            }
            if (slot && !rejected) {
                access[*slot] = std::move(*returnedAccess);
                peers[*slot] = std::move(*it);
                auto& q = *peers[*slot];
                q.accepted = true;
                q.waiting = true;
                Writer w(Message::welcome);
                w.u8(*slot);
                q.sendMessage(w);
                Writer wait(Message::waitFloor);
                wait.u8(playerCount);
                for (const auto character : startSettings.characters)
                    wait.u16(character);
                wait.string("");
                q.sendMessage(wait);
                updateMods(true);
            }
            if (slot || rejected)
                it = incoming.erase(it);
            else
                ++it;
        }
    }
};
Session::Session(void (*logger)(const std::string&), Observer observer, bool debugLogs,
                 Transport transport)
    : impl(std::make_unique<Impl>(logger, observer, debugLogs, transport)) {}
Session::~Session() = default;
bool Session::host(std::uint16_t port, const std::string& fingerprint, const std::string& mods,
                   const LobbyAccess& access) {
    if (!impl->winsock || impl->state != Phase::idle || fingerprint.empty() || !access.valid())
        return false;
    try {
        if (impl->transport == Transport::udp) {
            impl->listener = impl->io->listenDatagram(port);
            impl->boundPort = impl->listener->port;
        } else {
            Socket setup(socket(AF_INET, SOCK_STREAM, IPPROTO_TCP));
            const auto listener = setup.handle;
            if (listener == INVALID_SOCKET)
                throw std::runtime_error("Cannot create LAN socket");
            configure(listener);
            BOOL exclusive = TRUE;
            setsockopt(listener, SOL_SOCKET, SO_EXCLUSIVEADDRUSE,
                       reinterpret_cast<const char*>(&exclusive), sizeof(exclusive));
            sockaddr_in a{};
            a.sin_family = AF_INET;
            a.sin_port = htons(port);
            a.sin_addr.s_addr = INADDR_ANY;
            if (bind(listener, reinterpret_cast<sockaddr*>(&a), sizeof(a)) || listen(listener, 3))
                throw std::runtime_error("LAN port is unavailable");
            int size = sizeof(a);
            if (getsockname(listener, reinterpret_cast<sockaddr*>(&a), &size))
                throw std::runtime_error("Cannot inspect LAN port");
            impl->listener = impl->io->listen(std::exchange(setup.handle, INVALID_SOCKET));
            impl->boundPort = ntohs(a.sin_port);
        }
        impl->hosting = true;
        impl->fingerprint = fingerprint;
        impl->mods = mods;
        impl->localAccess = impl->access[0] = access;
        impl->state = Phase::lobby;
        return true;
    } catch (const std::exception& e) {
        impl->fail(e.what());
        return false;
    }
}
bool Session::join(const std::string& ip, std::uint16_t port, const std::string& fingerprint,
                   const std::string& identity, const std::string& mods,
                   const LobbyAccess& access) {
    if (!impl->winsock || impl->state != Phase::idle || fingerprint.empty() || !access.valid())
        return false;
    try {
        impl->identity = identity.empty() ? randomIdentity() : identity;
        if (!validIdentity(impl->identity))
            throw std::runtime_error("Invalid player identity");
        if (!validHostAddress(ip))
            throw std::runtime_error("Enter a valid IPv4 address or host name");
        impl->fingerprint = fingerprint;
        impl->mods = mods;
        impl->localAccess = access;
        impl->hostIP = ip;
        impl->boundPort = port;
        impl->state = Phase::connecting;
        impl->joinAt = Clock::now();
        sockaddr_in address{};
        address.sin_family = AF_INET;
        address.sin_port = htons(port);
        if (InetPtonA(AF_INET, ip.c_str(), &address.sin_addr) == 1) {
            impl->hostAddresses.push_back(address);
            impl->connectNextAddress();
        } else {
            impl->resolving = resolveHost(ip, port);
        }
        return true;
    } catch (const std::exception& e) {
        impl->fail(e.what());
        return false;
    }
}
bool Session::reconnect() {
    if (impl->hosting || (impl->state != Phase::failed && impl->state != Phase::closed) ||
        impl->hostIP.empty())
        return false;
    std::erase_if(retiring, [](const auto& value) { return value->workersFinished(); });
    constexpr std::size_t maxRetiringConnections = 2;
    if (retiring.size() >= maxRetiringConnections)
        return false;
    const auto ip = impl->hostIP, identity = impl->identity, fingerprint = impl->fingerprint,
               mods = impl->mods;
    const auto port = impl->boundPort;
    const auto logger = impl->logger;
    const auto observer = impl->observer;
    const auto debug = impl->debugLogs;
    const auto transport = impl->transport;
    const auto choices = impl->choices;
    const auto access = impl->localAccess;
    impl->shutdown();
    retiring.push_back(std::move(impl));
    impl = std::make_unique<Impl>(logger, observer, debug, transport);
    impl->choices = choices;
    return join(ip, port, fingerprint, identity, mods, access);
}
bool Session::beginStage(const Stage& value) {
    if (!impl->hosting || impl->state != Phase::running || impl->ending)
        return false;
    if (value.sourceRoom < -20 || value.sourceRoom >= 169 || value.restart > 2 ||
        (value.restart && (value.same || value.animation || value.level != 1 || value.type ||
                           !value.rewind.empty() || value.cinematic)) ||
        impl->cinematicEpoch ||
        (value.cinematic &&
         (value.cinematic != 25 || value.level != 13 || value.type != 1 || value.animation != 1 ||
          value.same || value.restart || !value.rewind.empty())))
        return false;
    if (value.cinematic) {
        impl->cinematicEpoch = value.epoch;
        impl->cinematicReadyMask = 0;
    }
    impl->integrationEpoch = value.epoch;
    for (auto& p : impl->peers)
        if (p)
            p->resetWorldCache(value.epoch);
    if (value.rewind.empty()) {
        impl->encodingStage.reset();
        impl->sendStage(value);
    } else {
        impl->encodingStage =
            impl->bulkWorker().submit([value = Stage(value)](StateCompression& codec) mutable {
                value.rewind = codec.compress(value.rewind);
                return value;
            });
    }
    impl->sendPending();
    for (unsigned slot = 1; slot < impl->playerCount; ++slot)
        if (auto& p = impl->peers[slot]; p) {
            try {
                p->flush();
            } catch (const std::exception&) {
                impl->remove(slot);
            }
        }
    return true;
}
std::optional<Stage> Session::takeStage() {
    auto value = impl->receivedStage;
    impl->receivedStage.reset();
    return value;
}
bool Session::cinematicActive() const {
    return impl->cinematicEpoch.has_value();
}
bool Session::cinematicReady() {
    if (impl->state != Phase::running || !impl->cinematicEpoch)
        return false;
    const unsigned bit = 1u << impl->localSlot;
    if (impl->cinematicReadyMask & bit)
        return true;
    impl->cinematicReadyMask |= bit;
    if (impl->hosting)
        impl->finishCinematic();
    else {
        Writer ready(Message::cinematic);
        ready.u32(*impl->cinematicEpoch);
        ready.u8(1);
        impl->peers[0]->sendMessage(ready);
    }
    return true;
}
bool Session::beginEnding(unsigned ending, const Progress& progress, bool completed) {
    if (!impl->hosting || impl->state != Phase::running || ending < ending::gameOver ||
        ending > ending::lastCinematic ||
        (completed && (!impl->runRules.id || ending == ending::gameOver)))
        return false;
    if (impl->ending)
        return *impl->ending == ending && impl->endingCompleted == completed;
    impl->ending = ending;
    impl->endingCompleted = completed;
    Writer w(Message::ending);
    w.u8(static_cast<std::uint8_t>(ending));
    w.u8(completed);
    w.progress(progress);
    for (unsigned slot = 1; slot < impl->playerCount; ++slot)
        if (auto& p = impl->peers[slot]; p && p->accepted && p->ready && !p->waiting) {
            // The terminal event precedes finish/EOF. Never append an unfinished
            // view after it, even when the engine exits during this update.
            try {
                p->resetWorldCache(impl->integrationEpoch);
                p->pending.reset();
                p->sendingStage.reset();
                p->sendMessage(w);
                p->flush();
            } catch (const std::exception&) {
                impl->remove(slot);
            }
        }
    return true;
}
std::optional<Ending> Session::takeEnding() {
    const auto value = impl->receivedEnding;
    impl->receivedEnding.reset();
    return value;
}
bool Session::requestRoom(const RoomRequest& value) {
    if (impl->hosting || impl->state != Phase::running || !impl->localReady)
        return false;
    Writer w(Message::roomRequest);
    w.u8(value.stage);
    w.u8(value.type);
    w.u8(value.sourceDimension);
    w.u8(value.dimension);
    w.u16(static_cast<std::uint16_t>(value.source));
    w.u16(static_cast<std::uint16_t>(value.destination));
    w.u8(value.teleport);
    impl->peers[0]->sendMessage(w);
    return true;
}
std::array<std::optional<RoomRequest>, maxPlayers> Session::takeRoomRequests() {
    auto result = std::move(impl->roomRequests);
    impl->roomRequests = {};
    return result;
}
bool Session::sendIntegration(unsigned destination, const std::string& bytes) {
    return impl->sendSideChannel(Message::integration, impl->integration, maxIntegrationSize,
                                 destination, bytes);
}
std::optional<IntegrationMessage> Session::takeIntegration() {
    return impl->integration.take();
}
bool Session::sendCommunication(unsigned destination, const std::string& bytes) {
    return impl->sendSideChannel(Message::communication, impl->communication, maxCommunicationSize,
                                 destination, bytes);
}
std::optional<IntegrationMessage> Session::takeCommunication() {
    return impl->communication.take();
}
const std::string& Session::runId() const {
    return impl->integrationRun;
}
std::uint32_t Session::worldEpoch() const {
    return impl->integrationEpoch;
}
void Session::poll() {
    std::erase_if(retiring, [](const auto& value) { return value->workersFinished(); });
    if (impl->state == Phase::failed || impl->state == Phase::closed || impl->state == Phase::idle)
        return;
    try {
        impl->finishBytes();
        if (impl->resolving) {
            if (!impl->resolving->ready.load(std::memory_order_acquire)) {
                if (Clock::now() - impl->joinAt > std::chrono::seconds(10))
                    throw std::runtime_error("Host name resolution timed out");
                return;
            }
            if (impl->resolving->error || impl->resolving->addresses.empty())
                throw std::runtime_error("Cannot resolve host name to an IPv4 address");
            impl->hostAddresses = std::move(impl->resolving->addresses);
            impl->resolving.reset();
            impl->connectNextAddress();
        }
        if (impl->listener) {
            if (impl->listener->failed.load(std::memory_order_acquire))
                throw std::runtime_error("LAN accept failed");
            if (auto accepted = impl->listener->accepted.pop()) {
                auto peer = std::make_unique<Peer>(impl->io, std::move(*accepted));
                if (impl->state == Phase::running && impl->incoming.size() < 3)
                    impl->incoming.push_back(std::move(peer));
                else {
                    unsigned slot = 1;
                    while (slot < maxPlayers && impl->peers[slot])
                        ++slot;
                    if (slot < maxPlayers && impl->state == Phase::lobby)
                        impl->peers[slot] = std::move(peer);
                }
            }
        }
        if (impl->connecting) {
            auto& p = *impl->peers[0];
            const auto status = p.pipe->state.load(std::memory_order_acquire);
            if (status == ConnectionPipe::failed || status == ConnectionPipe::closed) {
                impl->connectNextAddress();
                return;
            }
            if (status != ConnectionPipe::connected) {
                if (Clock::now() - impl->joinAt > std::chrono::seconds(10))
                    throw std::runtime_error("Host connection timed out");
                return;
            }
            impl->connecting = false;
            Writer hello(Message::hello);
            hello.u16(protocolVersion);
            hello.string(impl->fingerprint);
            hello.string(impl->identity);
            hello.string(impl->mods);
            hello.access(impl->localAccess);
            p.sendMessage(hello);
        }
        for (unsigned i = 0; i < maxPlayers; ++i)
            if (impl->peers[i]) {
                auto& p = *impl->peers[i];
                try {
                    if (!p.accepted && Clock::now() - p.connectedAt > std::chrono::seconds(10))
                        throw std::runtime_error("Handshake timed out");
                    p.flush();
                    p.receive(
                        [&](Reader& r) {
                            impl->message(i, r);
                            p.packetAt = Clock::now();
                        },
                        [&](WorldState value) {
                            if (impl->transport == Transport::udp && !impl->hosting &&
                                (impl->state != Phase::running ||
                                 value.epoch != impl->integrationEpoch ||
                                 (impl->verified && value.tick <= *impl->verified)))
                                return;
                            if (impl->hosting || impl->state != Phase::running ||
                                value.epoch != impl->integrationEpoch ||
                                value.connected >= (1u << impl->playerCount) ||
                                value.pauseOwner >= impl->playerCount ||
                                (impl->verified && value.tick <= *impl->verified))
                                throw std::runtime_error("Unexpected decoded world state");
                            impl->receivedState = std::move(value);
                            impl->progress = p.packetAt = Clock::now();
                        },
                        [&] {
                            return impl->decodingStage != nullptr ||
                                   impl->decodingCheckpoint != nullptr;
                        },
                        [&](ReceivedBulk value) {
                            impl->receiveBulk(std::move(value));
                            p.packetAt = Clock::now();
                        });
                    while (auto sample = p.pipe->samples.pop())
                        if (impl->observer)
                            impl->observer(sample->name, sample->milliseconds);
                    while (auto trace = p.pipe->traces.pop())
                        if (impl->logger && impl->debugLogs)
                            impl->logger("state_transfer slot=" + std::to_string(i) +
                                         " tick=" + std::to_string(trace->tick) +
                                         " raw=" + std::to_string(trace->raw) +
                                         " wire=" + std::to_string(trace->wire) +
                                         " full_wire=" + std::to_string(trace->full) +
                                         " delta=" + std::to_string(trace->delta) +
                                         " base=" + std::to_string(trace->base));
                    if (impl->hosting && !p.ready && p.loadingAt &&
                        Clock::now() - *p.loadingAt > std::chrono::seconds(60))
                        throw ConnectionLost("Player loading timed out");
                    if (impl->hosting && impl->initialStarted && p.ready &&
                        Clock::now() -
                                (impl->cinematicEpoch || impl->ending ? p.packetAt : p.inputAt) >
                            std::chrono::seconds(15))
                        throw ConnectionLost("Player connection timed out");
                } catch (const std::exception& e) {
                    if (!impl->hosting)
                        throw;
                    if (impl->logger)
                        impl->logger("network_peer_removed slot=" + std::to_string(i) +
                                     " reason=" + e.what());
                    try {
                        Writer w(Message::error);
                        w.string(std::string(e.what()).substr(0, 240));
                        p.sendMessage(w);
                        p.flush();
                    } catch (...) {
                    }
                    impl->remove(i);
                    if (impl->state == Phase::lobby) {
                        impl->choices[i] = {};
                        impl->identities[i].clear();
                        impl->lobbyDirty = true;
                    }
                }
            }
        impl->finishReturn();
        if (impl->hosting && impl->lobbyDirty)
            impl->lobby();
        if (impl->hosting) {
            impl->receiveReturning();
            impl->updateMods();
            impl->measureLatency();
            impl->finishCinematic();
            impl->sendPending();
        }
        for (unsigned i = 0; i < maxPlayers; ++i)
            if (impl->peers[i]) {
                try {
                    impl->peers[i]->flush();
                } catch (const std::exception&) {
                    if (!impl->hosting)
                        throw;
                    impl->remove(i);
                }
            }
        if (impl->state == Phase::finishing) {
            const bool drained =
                std::all_of(impl->peers.begin(), impl->peers.end(),
                            [](const auto& p) { return !p || p->queuedBytes() == 0; });
            if (drained || Clock::now() - impl->progress > std::chrono::seconds(5)) {
                impl->shutdown();
                impl->state = Phase::closed;
            }
        }
        if (!impl->hosting && (impl->state == Phase::running || impl->state == Phase::returning) &&
            impl->localReady &&
            Clock::now() - ((impl->cinematicEpoch || impl->ending) && impl->peers[0]
                                ? impl->peers[0]->packetAt
                                : impl->progress) >
                std::chrono::seconds(impl->verified ? 20 : 90))
            throw std::runtime_error("Host state transfer timed out");
    } catch (const std::exception& e) {
        impl->fail(e.what());
    }
}
void Session::close() {
    Writer bye(Message::goodbye);
    for (auto& p : impl->peers)
        if (p) {
            try {
                p->sendMessage(bye);
                p->flush();
            } catch (...) {
            }
        }
    impl->shutdown();
    impl->state = Phase::closed;
}
bool Session::returnToLobby() {
    if (impl->state == Phase::returning)
        return true;
    if (impl->state != Phase::running || !impl->ending || *impl->ending == ending::gameOver)
        return false;
    if (!impl->hosting) {
        Writer request(Message::returnLobby);
        request.string(impl->integrationRun);
        impl->peers[0]->sendMessage(request);
    }
    impl->returnedMask |= 1u << impl->localSlot;
    impl->state = Phase::returning;
    return true;
}
void Session::finish() {
    if (!impl->hosting || impl->state != Phase::running) {
        close();
        return;
    }
    try {
        Writer w(Message::finish);
        w.u32(impl->nextConsume);
        impl->broadcast(w);
        impl->state = Phase::finishing;
        impl->progress = Clock::now();
        for (auto& peer : impl->peers)
            if (peer)
                peer->flush();
    } catch (const std::exception& e) {
        impl->fail(e.what());
    }
}
void Session::abort(const std::string& reason) {
    impl->fail(reason);
}
bool Session::start(const Start& settings) {
    if (!impl->hosting || impl->state != Phase::lobby || impl->playerCount < 2 ||
        settings.seed.size() != 8 || settings.difficulty > 3 ||
        settings.snapshot.size() > maxSnapshotSize || settings.rules != impl->runRules ||
        !impl->rulesAvailable(settings.rules, !settings.snapshot.empty()))
        return false;
    for (unsigned i = 1; i < maxPlayers; ++i)
        if ((i < impl->playerCount && (!impl->peers[i] || !impl->peers[i]->accepted)) ||
            (i >= impl->playerCount && impl->peers[i]))
            return false;
    if (impl->choicesRequired)
        for (unsigned i = 0; i < impl->playerCount; ++i)
            if (!impl->choices[i].ready ||
                (settings.snapshot.empty() && impl->choices[i].character != settings.characters[i]))
                return false;
    if ((settings.rules.difficulty != 255 && settings.difficulty != settings.rules.difficulty))
        return false;
    for (unsigned i = 0; i < impl->playerCount; ++i)
        if (!impl->access[i].allowsCharacter(settings.characters[i], !settings.snapshot.empty()) ||
            (settings.rules.character != 65535 &&
             settings.characters[i] != settings.rules.character))
            return false;
    impl->integrationRun = randomIdentity();
    impl->integrationEpoch = 0;
    impl->integration.queue.clear();
    impl->startSettings = settings;
    impl->startSettings.firstTick = 0;
    impl->activeMask = (1u << impl->playerCount) - 1;
    impl->startSettings.connected = impl->activeMask;
    if (settings.snapshot.empty())
        impl->broadcast(impl->startMessage(Message::start, impl->startSettings));
    for (auto& p : impl->peers)
        if (p)
            p->loadingAt = Clock::now();
    if (!settings.snapshot.empty()) {
        const auto job = prepareCheckpoint(impl->bulkWorker(), impl->startSettings);
        for (auto& p : impl->peers)
            if (p)
                p->preparingCheckpoint = job;
    }
    impl->state = Phase::running;
    impl->progress = Clock::now();
    return true;
}
bool Session::restart(const Start& settings) {
    if (!impl->hosting || impl->state != Phase::running || !impl->localReady ||
        impl->cinematicEpoch || settings.seed.size() != 8 || !settings.snapshot.empty() ||
        settings.rules != impl->runRules || settings.characters != impl->startSettings.characters ||
        settings.difficulty != impl->startSettings.difficulty)
        return false;
    // A checkpoint loader still owns its previous run transaction. Wait for
    // that boundary rather than interrupting a partially transferred archive.
    for (const auto& peer : impl->peers)
        if (peer && peer->accepted && (!peer->ready || peer->waiting || peer->rejoining))
            return false;
    for (unsigned slot = 0; slot < impl->playerCount; ++slot)
        if ((impl->activeMask & (1u << slot)) &&
            (!impl->access[slot].allowsRules(settings.rules) ||
             !impl->access[slot].allowsCharacter(settings.characters[slot]) ||
             (slot && (!impl->peers[slot] || !impl->peers[slot]->ready))))
            return false;
    ++impl->integrationEpoch;
    impl->integrationRun = randomIdentity();
    impl->startSettings = settings;
    impl->startSettings.firstTick = 0;
    impl->startSettings.connected = impl->activeMask;
    const auto message = impl->startMessage(Message::restart, impl->startSettings);
    impl->resetRun();
    for (unsigned slot = 1; slot < impl->playerCount; ++slot)
        if ((impl->activeMask & (1u << slot)) && impl->peers[slot])
            impl->peers[slot]->sendMessage(message);
    impl->restartPending = true;
    return true;
}
bool Session::takeRestart() {
    const bool pending = impl->restartPending;
    impl->restartPending = false;
    return pending;
}
bool Session::sendLifecycle(unsigned destination, const std::string& bytes) {
    // Consumers discard lifecycle messages until their new run is ready.
    // Report that boundary to the caller so initial vote state is retried.
    if (impl->state != Phase::running || !impl->localReady || destination >= impl->playerCount)
        return false;
    if (impl->hosting && destination) {
        const auto& peer = impl->peers[destination];
        if (!peer || !peer->ready || peer->waiting || peer->rejoining)
            return false;
    }
    return impl->sendSideChannel(Message::lifecycle, impl->lifecycle, maxIntegrationSize,
                                 destination, bytes);
}
std::optional<IntegrationMessage> Session::takeLifecycle() {
    return impl->lifecycle.take();
}
bool Session::checkpoint(const Start& settings, std::uint32_t tick) {
    if (!impl->hosting || impl->state != Phase::running || settings.snapshot.empty() ||
        settings.snapshot.size() > maxSnapshotSize || tick != impl->committed ||
        settings.rules != impl->runRules)
        return false;
    impl->startSettings = settings.metadata();
    impl->startSettings.firstTick = tick;
    impl->startSettings.connected = impl->activeMask;
    auto saved = impl->startSettings;
    saved.snapshot = settings.snapshot;
    const auto job = prepareCheckpoint(impl->bulkWorker(), std::move(saved));
    for (unsigned slot = 1; slot < impl->playerCount; ++slot)
        if (auto& p = impl->peers[slot]; p && p->accepted && p->waiting) {
            impl->latest[slot] = {};
            impl->inputRooms[slot].reset();
            impl->commands[slot] = Command::none;
            p->ready = false;
            p->loadingAt = Clock::now();
            p->loaded = false;
            p->checkpointQueued = false;
            p->pipe->checkpointSent.store(0);
            p->preparingCheckpoint = job;
            p->pending.reset();
            // Finish a partly transmitted view before the checkpoint header.
            // All queued chunks are bounded; the receiver discards the old view.
            p->resetWorldCache(impl->integrationEpoch);
            p->rejoining = true;

            p->waiting = false;
        }
    return true;
}
bool Session::checkpointNeeded() const {
    if (!impl->hosting || impl->state != Phase::running)
        return false;
    return std::any_of(impl->peers.begin(), impl->peers.end(),
                       [](const auto& p) { return p && p->accepted && p->waiting; });
}
bool Session::choose(Choice choice) {
    if (impl->state != Phase::lobby ||
        (impl->runRules.character != 65535 && choice.character != impl->runRules.character) ||
        !impl->localAccess.allowsCharacter(choice.character) ||
        (choice.ready && !impl->rulesAvailable(impl->runRules)))
        return false;
    if (impl->hosting) {
        impl->choices[0] = choice;
        impl->choicesRequired = true;
        impl->lobbyDirty = true;
    } else {
        Writer w(Message::choice);
        w.u32(impl->rulesRevision);
        w.u16(choice.character);
        w.u8(choice.ready);
        impl->peers[0]->sendMessage(w);
    }
    return true;
}
bool Session::configureRules(const RunRules& rules) {
    if (!impl->hosting || impl->state != Phase::lobby || !impl->rulesAvailable(rules))
        return false;
    if (rules == impl->runRules)
        return true;
    impl->runRules = rules;
    ++impl->rulesRevision;
    for (unsigned i = 0; i < maxPlayers; ++i) {
        auto& choice = impl->choices[i];
        choice.ready = false;
        if (rules.character != 65535)
            choice.character = rules.character;
        else if (!impl->access[i].allowsCharacter(choice.character) &&
                 !impl->access[i].characters.empty())
            choice.character = impl->access[i].characters.front();
    }
    impl->choicesRequired = true;
    impl->lobbyDirty = true;
    return true;
}
bool Session::rulesAvailable(const RunRules& rules) const {
    return impl->rulesAvailable(rules);
}
const LobbyAccess& Session::localAccess() const {
    return impl->localAccess;
}
const std::array<LobbyAccess, maxPlayers>& Session::access() const {
    return impl->access;
}
const RunRules& Session::rules() const {
    return impl->runRules;
}
const std::array<Choice, maxPlayers>& Session::choices() const {
    return impl->choices;
}
bool Session::command(Command c) {
    if (impl->state != Phase::running || c == Command::none || c > Command::leave ||
        (!impl->hosting && c == Command::saveExit) || (impl->hosting && c == Command::leave))
        return false;
    if (c == Command::leave) {
        close();
        return true;
    }
    if (impl->hosting)
        impl->commands[0] = c;
    else {
        Writer w(Message::control);
        w.u8(static_cast<unsigned>(c));
        impl->peers[0]->sendMessage(w);
    }
    return true;
}
bool Session::submit(std::uint32_t sequence, const InputFrame& input,
                     std::optional<InputRoom> room) {
    if (impl->state != Phase::running || sequence != impl->nextInput)
        return false;
    if (impl->hosting) {
        const auto edges = impl->latest[0].triggered;
        impl->latest[0] = input;
        impl->latest[0].triggered |= edges;
        impl->sequences[0] = sequence;
        impl->inputRooms[0] = room;
    } else {
        impl->peers[0]->submitInput({sequence, input, room});
    }
    ++impl->nextInput;
    return true;
}
std::optional<Frame> Session::take() {
    if (!impl->hosting || impl->state != Phase::running || impl->cinematicEpoch ||
        !impl->localReady || !impl->nextInput)
        return {};
    // A host exit must be consumable while a guest is still loading.
    // The runtime already has its native roster when localReady is true.
    if (!impl->initialStarted && impl->commands[0] != Command::saveExit) {
        for (unsigned i = 1; i < impl->playerCount; ++i)
            if ((impl->activeMask & (1u << i)) && impl->peers[i] && !impl->peers[i]->ready)
                return {};
        impl->initialStarted = true;
        for (auto& p : impl->peers)
            if (p && p->ready)
                p->inputAt = Clock::now();
    }
    if (impl->consumedLocal == impl->sequences[0])
        return {};
    impl->consumedLocal = impl->sequences[0];
    Frame frame;
    frame.tick = impl->nextConsume++;
    frame.players = impl->playerCount;
    for (unsigned i = 1; i < impl->playerCount; ++i) {
        if (impl->commands[i] == Command::leave) {
            impl->remove(i);
            continue;
        }
        if (impl->peers[i] &&
            Clock::now() - impl->peers[i]->inputAt > std::chrono::milliseconds(500))
            impl->latest[i] = {};
    }
    frame.connected = impl->activeMask;
    frame.commands = impl->commands;
    impl->commands = {};
    for (unsigned i = 0; i < impl->playerCount; ++i) {
        if (impl->activeMask & (1u << i))
            frame.inputs[i] = impl->latest[i];
        frame.inputRooms[i] = impl->inputRooms[i];
        if (impl->peers[i] && (impl->activeMask & (1u << i)))
            impl->peers[i]->consumeEdges(frame.inputs[i], frame.inputRooms[i]);
        impl->latest[i].triggered = 0;
    }
    impl->progress = Clock::now();
    return frame;
}
bool Session::ready() {
    if (impl->state != Phase::running)
        return false;
    impl->localReady = true;
    impl->progress = Clock::now();
    if (!impl->hosting) {
        Writer w(Message::ready);
        w.string(impl->integrationRun);
        w.u32(impl->startSettings.firstTick);
        impl->peers[0]->sendMessage(w);
    }
    return true;
}
bool Session::publish(unsigned slot, const WorldState& state) {
    if (!impl->hosting || impl->state != Phase::running || impl->ending || impl->cinematicEpoch ||
        !slot || slot >= impl->playerCount || state.bytes.empty() ||
        state.bytes.size() + state.stable.size() + (state.stable.empty() ? 0 : 4) > maxWorldSize ||
        state.tick >= impl->nextConsume)
        return false;
    if (auto& p = impl->peers[slot]; p && p->ready)
        p->pending = state;
    return true;
}
std::optional<WorldState> Session::takeState() {
    if (impl->hosting || !impl->localReady || !impl->receivedState)
        return {};
    auto value = std::move(impl->receivedState);
    impl->receivedState.reset();
    impl->activeMask = value->connected;
    impl->takenWorldEpoch = value->epoch;
    return value;
}
void Session::applied(std::uint32_t tick) {
    if (impl->hosting || impl->state != Phase::running ||
        (impl->verified && tick <= *impl->verified))
        return;
    impl->verified = tick;
    impl->nextConsume = tick + 1;
    Writer w(Message::applied);
    w.u32(impl->takenWorldEpoch);
    w.u32(tick);
    impl->peers[0]->sendMessage(w);
}
void Session::completed(std::uint32_t tick) {
    if (impl->hosting) {
        impl->committed = tick + 1;
        impl->verified = tick;
    }
}
std::array<std::uint32_t, maxPlayers> Session::inputSequences() const {
    return impl->sequences;
}
const std::array<int, maxPlayers>& Session::latency() const {
    return impl->latency;
}
const std::string& Session::identity() const {
    return impl->identity;
}
Phase Session::phase() const {
    return impl->state;
}
unsigned Session::slot() const {
    return impl->localSlot;
}
unsigned Session::players() const {
    return impl->playerCount;
}
unsigned Session::connectedMask() const {
    return impl->activeMask;
}
bool Session::isHost() const {
    return impl->hosting;
}
bool Session::modsDiffer() const {
    return impl->modMismatch;
}
const std::string& Session::error() const {
    return impl->failure;
}
const Start& Session::settings() const {
    return impl->startSettings;
}
std::optional<std::uint32_t> Session::verifiedTick() const {
    return impl->verified;
}
std::uint16_t Session::port() const {
    return impl->boundPort;
}
TransportResources Session::resources() const {
    TransportResources out;
    out.worldSnapshots = impl->worldSnapshots;
    out.deltaSnapshots = impl->deltaSnapshots;
    out.rawWorldBytes = impl->rawWorldBytes;
    out.wireWorldBytes = impl->wireWorldBytes;
    out.fullWorldBytes = impl->fullWorldBytes;
    out.connections = impl->listener != nullptr;
    const auto observe = [&out](const auto& p) {
        if (!p)
            return;
        ++out.connections;
        out.queuedBytes += p->queuedBytes();
        out.receiveCapacity +=
            p->pipe ? p->pipe->receiveCapacity.load(std::memory_order_acquire) : 0;
        out.cachedWorldBytes += p->cachedBytes();
        out.inFlightBytes += p->inFlightBytes();
        if (p->pipe) {
            const auto& world = p->pipe->world;
            out.inFlightStates += world.flightStates.load();
            out.coalescedInputs += p->coalescedInputs + p->pipe->coalescedInputs.load();
            out.deliveryWindow += p->window();
            out.oldestWorldMs = std::max<std::uint64_t>(out.oldestWorldMs, world.oldestMs.load());
            out.worldBytes += world.worldBytes.load();
            out.worldSnapshots += world.snapshots.load();
            out.deltaSnapshots += world.deltas.load();
            out.rawWorldBytes += world.raw.load();
            out.wireWorldBytes += world.wire.load();
            out.fullWorldBytes += world.full.load();
        }
        if (p->pending)
            out.worldBytes += p->pending->bytes.capacity();
    };
    for (const auto& p : impl->peers)
        observe(p);
    for (const auto& p : impl->incoming)
        observe(p);
    if (impl->receivedState)
        out.worldBytes += impl->receivedState->bytes.capacity();
    return out;
}
} // namespace isaac::lan

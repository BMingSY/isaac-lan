#pragma once
#include "net/protocol.h"
#include <memory>
#include <optional>

namespace isaac::lan {
struct TransportResources {
    std::size_t connections = 0, queuedBytes = 0, receiveCapacity = 0, worldBytes = 0;
    std::size_t cachedWorldBytes = 0, inFlightBytes = 0, inFlightStates = 0;
    std::size_t deliveryWindow = 0;
    std::uint64_t oldestWorldMs = 0, coalescedInputs = 0;
    std::uint64_t worldSnapshots = 0, deltaSnapshots = 0, rawWorldBytes = 0, wireWorldBytes = 0,
                  fullWorldBytes = 0;
};
// Main-thread, nonblocking TCP transport. No external server and no Lua calls on
// worker threads. TCP_NODELAY is set on every connected socket.
class Session {
    struct Impl;
    std::unique_ptr<Impl> impl;

  public:
    using Observer = void (*)(std::string_view, double);
    explicit Session(void (*logger)(const std::string&) = nullptr, Observer observer = nullptr,
                     bool debugLogs = false);
    ~Session();
    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;
    bool host(std::uint16_t port, const std::string& fingerprint, const std::string& mods = {},
              const LobbyAccess& access = {});
    bool join(const std::string& address, std::uint16_t port, const std::string& fingerprint,
              const std::string& identity = {}, const std::string& mods = {},
              const LobbyAccess& access = {});
    bool reconnect();
    void poll();
    void close();
    void finish();
    void abort(const std::string& reason);
    bool start(const Start& settings);
    // Admit waiting guests from a native current-floor save. Loading never
    // stalls the live session; the first live view uses the host's latest room.
    bool checkpoint(const Start& settings, std::uint32_t firstTick);
    bool checkpointNeeded() const;
    bool choose(Choice choice);
    bool configureRules(const RunRules& rules);
    bool rulesAvailable(const RunRules& rules) const;
    const LobbyAccess& localAccess() const;
    const std::array<LobbyAccess, maxPlayers>& access() const;
    const RunRules& rules() const;
    bool command(Command command);
    const std::array<Choice, maxPlayers>& choices() const;
    bool submit(std::uint32_t tick, const InputFrame& input, std::optional<InputRoom> room = {});
    // Only the host consumes inputs; missing remote samples never stall it.
    std::optional<Frame> take();
    bool ready();
    bool publish(unsigned slot, const WorldState& state);
    std::optional<WorldState> takeState();
    bool beginStage(const Stage&);
    std::optional<Stage> takeStage();
    bool cinematicReady();
    bool cinematicActive() const;
    bool beginEnding(unsigned ending, const Progress& progress = {}, bool completed = false);
    std::optional<Ending> takeEnding();
    bool requestRoom(const RoomRequest&);
    std::array<std::optional<RoomRequest>, maxPlayers> takeRoomRequests();
    bool sendIntegration(unsigned destination, const std::string& bytes);
    std::optional<IntegrationMessage> takeIntegration();
    bool sendCommunication(unsigned destination, const std::string& bytes);
    std::optional<IntegrationMessage> takeCommunication();
    const std::string& runId() const;
    std::uint32_t worldEpoch() const;
    void applied(std::uint32_t tick);
    std::array<std::uint32_t, maxPlayers> inputSequences() const;
    const std::array<int, maxPlayers>& latency() const;
    void completed(std::uint32_t tick);
    const std::string& identity() const;
    Phase phase() const;
    unsigned slot() const;
    unsigned players() const;
    unsigned connectedMask() const;
    bool isHost() const;
    bool modsDiffer() const;
    const std::string& error() const;
    const Start& settings() const;
    std::optional<std::uint32_t> verifiedTick() const;
    std::uint16_t port() const;
    TransportResources resources() const;
};
} // namespace isaac::lan

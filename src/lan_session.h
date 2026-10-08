#pragma once
#include "net_protocol.h"
#include <memory>
#include <optional>

namespace isaac::lan {
// Main-thread, nonblocking TCP transport. No external server and no Lua calls on
// worker threads. TCP_NODELAY is set on every connected socket.
class Session {
    struct Impl;
    std::unique_ptr<Impl> impl;

  public:
    explicit Session(void (*logger)(const std::string&) = nullptr);
    ~Session();
    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;
    bool host(std::uint16_t port, const std::string& fingerprint, const std::string& mods = {});
    bool join(const std::string& ipv4, std::uint16_t port, const std::string& fingerprint,
              const std::string& identity = {}, const std::string& mods = {});
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
    bool command(Command command);
    const std::array<Choice, maxPlayers>& choices() const;
    bool submit(std::uint32_t tick, const InputFrame& input);
    // Only the host consumes inputs; missing remote samples never stall it.
    std::optional<Frame> take();
    bool ready();
    bool publish(unsigned slot, const WorldState& state);
    std::optional<WorldState> takeState();
    bool beginStage(const Stage&);
    std::optional<Stage> takeStage();
    bool requestRoom(const RoomRequest&);
    std::array<std::optional<RoomRequest>, maxPlayers> takeRoomRequests();
    bool sendIntegration(unsigned destination, const std::string& bytes);
    std::optional<IntegrationMessage> takeIntegration();
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
};
} // namespace isaac::lan

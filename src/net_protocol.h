#pragma once
#include <array>
#include <cstdint>
#include <span>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace isaac::lan {
constexpr std::uint16_t protocolVersion = 24;
constexpr std::size_t maxPlayers = 4;
constexpr std::size_t actionCount = 16;
constexpr std::size_t maxMessageSize = 4096;
constexpr std::size_t maxSnapshotSize = 8 * 1024 * 1024;
constexpr std::size_t maxWorldSize = 2 * 1024 * 1024;
enum class Message : std::uint8_t {
    hello = 1,
    welcome,
    lobby,
    start,
    input,
    error,
    goodbye,
    choice,
    finish,
    snapshot,
    loaded,
    control,
    waitFloor,
    modStatus,
    world,
    applied,
    ready,
    stage,
    roomRequest,
    ping,
    pong,
    latency,
    integration,
    ending,
    cinematic
};
constexpr std::size_t maxIntegrationSize = 2048;
constexpr std::size_t maxIntegrationQueue = 32;
struct IntegrationMessage {
    unsigned sender = 0; // Assigned by the transport, never supplied in a payload.
    std::string bytes;
};
enum class Phase {
    idle,
    connecting,
    lobby,
    running,
    failed,
    closed,
    finishing,
    loading,
    leaving,
    waiting
};
enum class Command : std::uint8_t { none, pause, resume, saveExit, leave };

struct InputFrame {
    std::array<std::uint16_t, actionCount> values{};
    std::uint16_t triggered = 0;
    bool operator==(const InputFrame&) const = default;
};
// Menu requests belong to the session, not to a room's movement epoch.
constexpr std::uint16_t menuActionMask = (1u << 12) | (1u << 15);
inline InputFrame menuInput(const InputFrame& input) {
    InputFrame result;
    result.values[12] = input.values[12];
    result.values[15] = input.values[15];
    result.triggered = input.triggered & menuActionMask;
    return result;
}
// Held controls belong to the room the sender has actually displayed.
struct InputRoom {
    std::uint32_t epoch = 0;
    std::int16_t index = 0;
    std::uint8_t dimension = 0;
    std::uint32_t introSerial = 0;
    bool introActive = false;
    bool operator==(const InputRoom&) const = default;
    bool sameRoom(const InputRoom& other) const {
        return epoch == other.epoch && index == other.index && dimension == other.dimension;
    }
};
struct Frame {
    std::uint32_t tick = 0;
    std::uint8_t players = 0;
    std::array<InputFrame, maxPlayers> inputs{};
    std::array<std::optional<InputRoom>, maxPlayers> inputRooms{};
    std::array<Command, maxPlayers> commands{};
    std::uint8_t connected = 15;
    bool operator==(const Frame&) const = default;
};
struct Progress {
    std::array<std::uint8_t, 642> achievements{};
    std::array<std::uint32_t, 523> counters{};
    bool operator==(const Progress&) const = default;
};
struct Ending {
    unsigned id = 0;
    Progress progress;
    bool operator==(const Ending&) const = default;
};
struct Start {
    std::uint32_t firstTick = 0;
    std::uint8_t connected = 0;
    std::string seed;
    std::uint8_t difficulty = 0;
    std::array<std::uint16_t, maxPlayers> characters{};
    std::optional<Progress> progress;
    std::vector<std::uint8_t> snapshot;
};
struct Choice {
    std::uint16_t character = 0;
    bool ready = false;
    bool operator==(const Choice&) const = default;
};
// Begin the game's native transition, rather than discovering a floor change
// in a snapshot after the host has finished loading it.
struct Stage {
    std::uint32_t epoch = 0;
    std::uint8_t level = 0, type = 0, animation = 0;
    bool same = false;
    // Empty for ordinary native floor transitions. Glowing Hourglass carries
    // one reliable native save transaction, split across bounded messages.
    std::vector<std::uint8_t> rewind;
    // Pointer-free native Seeds fields: start seed, RNG, floor seeds and
    // player-init seed. Regeneration items alter them before the transition.
    std::array<std::uint32_t, 21> seeds{};
    // R Key runs a native immediate restart, not a stage animation.
    bool rKey = false;
    // Native GameStateFlag bits select the next route. Replica players do not
    // simulate the trapdoor that sets STATE_SECRET_PATH before an alt entrance.
    std::array<std::uint32_t, 2> stateFlags{};
    // Native Dogma interlude changes to the Beast arena on the same floor.
    std::uint8_t cinematic = 0;
    bool operator==(const Stage&) const = default;
};
// A local Mod's native room command, not a client-authored world snapshot.
// The host validates its source floor/room before executing the transition.
struct RoomRequest {
    std::uint8_t stage = 0, type = 0, sourceDimension = 0, dimension = 0;
    std::int16_t source = 0, destination = 0;
    bool teleport = false;
    bool operator==(const RoomRequest&) const = default;
};

// A complete authoritative view. Input sequence numbers acknowledge controls,
// not deterministic simulation frames. Older unsent views may be replaced.
struct WorldState {
    std::uint32_t tick = 0;
    std::uint8_t connected = 1;
    std::uint8_t pauseOwner = 0;
    bool paused = false;
    std::array<std::uint32_t, maxPlayers> inputSequences{};
    std::vector<std::uint8_t> bytes;
};

class Writer {
  public:
    std::vector<std::uint8_t> bytes;
    explicit Writer(Message type) {
        u8(static_cast<std::uint8_t>(type));
    }
    void u8(std::uint8_t n) {
        bytes.push_back(n);
    }
    void u16(std::uint16_t n) {
        u8(n >> 8);
        u8(n & 255);
    }
    void u32(std::uint32_t n) {
        u16(n >> 16);
        u16(n & 65535);
    }
    void u64(std::uint64_t n) {
        u32(n >> 32);
        u32(n & 0xffffffff);
    }
    void string(const std::string& s) {
        if (s.size() > 1024)
            throw std::runtime_error("Protocol string too long");
        u16(static_cast<std::uint16_t>(s.size()));
        bytes.insert(bytes.end(), s.begin(), s.end());
    }
    void input(const InputFrame& i) {
        for (auto n : i.values)
            u16(n);
        u16(i.triggered);
    }
    void blob(std::span<const std::uint8_t> value) {
        if (value.size() > maxSnapshotSize)
            throw std::runtime_error("Snapshot exceeds size limit");
        u32(static_cast<std::uint32_t>(value.size()));
        bytes.insert(bytes.end(), value.begin(), value.end());
    }
    void progress(const std::optional<Progress>& p) {
        u8(p.has_value());
        if (p) {
            for (auto n : p->achievements)
                u8(n);
            for (auto n : p->counters)
                u32(n);
        }
    }
};

class Reader {
    std::span<const std::uint8_t> bytes;
    std::size_t cursor = 0;

  public:
    explicit Reader(std::span<const std::uint8_t> b) : bytes(b) {}
    std::uint8_t u8() {
        if (cursor >= bytes.size())
            throw std::runtime_error("Truncated protocol message");
        return bytes[cursor++];
    }
    std::uint16_t u16() {
        auto a = u8();
        return static_cast<std::uint16_t>((a << 8) | u8());
    }
    std::uint32_t u32() {
        auto a = u16();
        return (static_cast<std::uint32_t>(a) << 16) | u16();
    }
    std::uint64_t u64() {
        auto a = u32();
        return (static_cast<std::uint64_t>(a) << 32) | u32();
    }
    std::string string() {
        auto size = u16();
        if (size > 1024 || size > bytes.size() - cursor)
            throw std::runtime_error("Invalid protocol string");
        std::string out(reinterpret_cast<const char*>(bytes.data() + cursor), size);
        cursor += size;
        return out;
    }
    InputFrame input() {
        InputFrame out;
        for (auto& n : out.values)
            n = u16();
        out.triggered = u16();
        return out;
    }
    std::vector<std::uint8_t> blob(std::size_t maximum = maxSnapshotSize) {
        const auto n = u32();
        if (n > maximum || n > bytes.size() - cursor)
            throw std::runtime_error("Invalid snapshot length");
        std::vector<std::uint8_t> out(bytes.begin() + cursor, bytes.begin() + cursor + n);
        cursor += n;
        return out;
    }
    std::optional<Progress> progress() {
        const auto present = u8();
        if (present > 1)
            throw std::runtime_error("Invalid progression state");
        if (!present)
            return std::nullopt;
        Progress out;
        for (auto& n : out.achievements) {
            n = u8();
            if (n > 1)
                throw std::runtime_error("Invalid achievement flag");
        }
        for (auto& n : out.counters)
            n = u32();
        return out;
    }
    void finish() const {
        if (cursor != bytes.size())
            throw std::runtime_error("Trailing protocol data");
    }
};
inline std::uint64_t snapshotHash(std::span<const std::uint8_t> bytes) {
    std::uint64_t hash = 14695981039346656037ull;
    for (auto byte : bytes) {
        hash ^= byte;
        hash *= 1099511628211ull;
    }
    return hash;
}
} // namespace isaac::lan

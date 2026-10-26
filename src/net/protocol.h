#pragma once
#include "core/run_rules.h"
#include "core/input_actions.h"
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <span>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace isaac::lan {
using RunRules = isaac::RunRules;
constexpr std::uint16_t protocolVersion = 46;
constexpr std::size_t maxPlayers = 4;
constexpr std::size_t actionCount = 16;
constexpr std::uint16_t maxInputValue = 65535;
constexpr unsigned allPlayersMask = (1u << maxPlayers) - 1;
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
    cinematic,
    communication,
    lifecycle,
    restart,
    returnLobby,
    inputEdges,
    choicePreview
};
constexpr std::size_t maxIntegrationSize = 2048;
constexpr std::size_t maxCommunicationSize = 3072;
constexpr std::size_t maxIntegrationQueue = 32;
struct IntegrationMessage {
    unsigned sender = 0; // Assigned by the transport, never supplied in a payload.
    std::string bytes;
};
enum class Phase {
    idle = 0,
    connecting = 1,
    lobby = 2,
    running = 3,
    failed = 4,
    closed = 5,
    finishing = 6,
    loading = 7,
    leaving = 8,
    waiting = 9,
    returning = 10,
};
inline constexpr std::array<std::pair<const char*, Phase>, 11> phaseValues{{
    {"idle", Phase::idle},
    {"connecting", Phase::connecting},
    {"lobby", Phase::lobby},
    {"running", Phase::running},
    {"failed", Phase::failed},
    {"closed", Phase::closed},
    {"finishing", Phase::finishing},
    {"loading", Phase::loading},
    {"leaving", Phase::leaving},
    {"waiting", Phase::waiting},
    {"returning", Phase::returning},
}};
enum class Command : std::uint8_t { none = 0, pause = 1, resume = 2, saveExit = 3, leave = 4 };
inline constexpr std::array<std::pair<const char*, Command>, 5> commandValues{{
    {"none", Command::none},
    {"pause", Command::pause},
    {"resume", Command::resume},
    {"saveExit", Command::saveExit},
    {"leave", Command::leave},
}};

struct PointerInput {
    bool active = false;
    float x = 0, y = 0;
    bool operator==(const PointerInput&) const = default;
};
inline bool validPointer(const PointerInput& pointer) {
    constexpr float coordinateLimit = 32768;
    return std::isfinite(pointer.x) && std::isfinite(pointer.y) &&
           std::abs(pointer.x) <= coordinateLimit && std::abs(pointer.y) <= coordinateLimit &&
           (pointer.active || (pointer.x == 0 && pointer.y == 0));
}
constexpr std::size_t inputWireSize = actionCount * 2 + 2 + 1 + 4 * 2;
struct InputFrame {
    std::array<std::uint16_t, actionCount> values{};
    std::uint16_t triggered = 0;
    PointerInput pointer;
    bool operator==(const InputFrame&) const = default;
};
// Menu requests belong to the session, not to a room's movement epoch.
constexpr std::uint16_t menuActionMask =
    (1u << input::action::menuPause) | (1u << input::action::menuBack);
inline InputFrame menuInput(const InputFrame& input) {
    InputFrame result;
    result.values[input::action::menuPause] = input.values[input::action::menuPause];
    result.values[input::action::menuBack] = input.values[input::action::menuBack];
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
namespace ending {
inline constexpr unsigned gameOver = 1;
inline constexpr unsigned firstCinematic = 2;
inline constexpr unsigned lastCinematic = 14;
} // namespace ending
struct Ending {
    unsigned id = 0;
    Progress progress;
    bool completed = false;
    bool operator==(const Ending&) const = default;
};
struct Start {
    RunRules rules;
    std::uint32_t firstTick = 0;
    std::uint8_t connected = 0;
    std::string seed;
    std::uint8_t difficulty = 0;
    std::array<std::uint16_t, maxPlayers> characters{};
    std::optional<Progress> progress;
    std::vector<std::uint8_t> snapshot;
    Start metadata() const {
        return {rules, firstTick, connected, seed, difficulty, characters, progress, {}};
    }
};
struct Choice {
    std::uint16_t character = 0;
    bool ready = false;
    // Opaque, bounded presentation metadata owned by this participant.
    std::uint32_t preview = 0;
    bool operator==(const Choice&) const = default;
};
struct RuleKey {
    std::uint16_t id = 0, version = 0;
    bool operator==(const RuleKey&) const = default;
    bool operator<(const RuleKey& other) const {
        return id < other.id || (id == other.id && version < other.version);
    }
};
// Bounded, immutable declarations from each participant's local profile. The
// transport only compares IDs; game-specific unlock rules live above it.
struct LobbyAccess {
    std::vector<std::uint16_t> characters;
    std::vector<RuleKey> rules;
    std::vector<std::uint16_t> unlockedCharacters;
    bool operator==(const LobbyAccess&) const = default;
    bool valid() const {
        if (characters.size() > 256 || unlockedCharacters.size() > 256 || rules.size() > 64)
            return false;
        for (const auto* list : {&characters, &unlockedCharacters})
            for (std::size_t i = 0; i < list->size(); ++i)
                if ((*list)[i] == 65535 || (i && (*list)[i - 1] >= (*list)[i]))
                    return false;
        if (!std::includes(unlockedCharacters.begin(), unlockedCharacters.end(), characters.begin(),
                           characters.end()))
            return false;
        for (std::size_t i = 0; i < rules.size(); ++i)
            if (!rules[i].id || !rules[i].version || (i && !(rules[i - 1] < rules[i])))
                return false;
        return true;
    }
    bool allowsCharacter(std::uint16_t character, bool continuing = false) const {
        const auto& values = continuing ? unlockedCharacters : characters;
        return std::binary_search(values.begin(), values.end(), character);
    }
    bool allowsRules(const RunRules& value, bool continuing = false) const {
        return value.valid() &&
               (!value.id ||
                std::binary_search(rules.begin(), rules.end(), RuleKey{value.id, value.version})) &&
               (value.character == 65535 || allowsCharacter(value.character, continuing));
    }
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
    // Opaque bounded native restart kind, interpreted by game compatibility.
    std::uint8_t restart = 0;
    // Native GameStateFlag bits select the next route. Replica players do not
    // simulate the trapdoor that sets STATE_SECRET_PATH before an alt entrance.
    std::array<std::uint32_t, 2> stateFlags{};
    // Native Dogma interlude changes to the Beast arena on the same floor.
    std::uint8_t cinematic = 0;
    // Authoritative departure context for native next-floor selection.
    std::int16_t sourceRoom = 0;
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
    std::uint32_t epoch = 0;
    std::uint8_t connected = 1;
    std::uint8_t pauseOwner = 0;
    bool paused = false;
    std::array<std::uint32_t, maxPlayers> inputSequences{};
    std::vector<std::uint8_t> bytes;
    // Opaque, less frequently changing dependency. The UDP worker assigns its
    // revision and only delivers a view with the exact matching dependency.
    std::vector<std::uint8_t> stable;
    std::uint32_t revision = 0;
};

class Writer {
  public:
    std::vector<std::uint8_t> bytes;
    explicit Writer(Message type, std::size_t capacity = 1) {
        bytes.reserve(capacity);
        u8(static_cast<std::uint8_t>(type));
    }
    void u8(std::uint8_t n) {
        bytes.push_back(n);
    }
    void u16(std::uint16_t n) {
        const auto at = bytes.size();
        bytes.resize(at + sizeof(n));
        bytes[at] = static_cast<std::uint8_t>(n >> 8);
        bytes[at + 1] = static_cast<std::uint8_t>(n);
    }
    void u32(std::uint32_t n) {
        const auto at = bytes.size();
        bytes.resize(at + sizeof(n));
        bytes[at] = static_cast<std::uint8_t>(n >> 24);
        bytes[at + 1] = static_cast<std::uint8_t>(n >> 16);
        bytes[at + 2] = static_cast<std::uint8_t>(n >> 8);
        bytes[at + 3] = static_cast<std::uint8_t>(n);
    }
    void u64(std::uint64_t n) {
        u32(n >> 32);
        u32(n & 0xffffffff);
    }
    void string(std::string_view s) {
        if (s.size() > 1024)
            throw std::runtime_error("Protocol string too long");
        u16(static_cast<std::uint16_t>(s.size()));
        bytes.insert(bytes.end(), s.begin(), s.end());
    }
    void input(const InputFrame& i) {
        if (!validPointer(i.pointer))
            throw std::runtime_error("Invalid input pointer");
        for (auto n : i.values)
            u16(n);
        u16(i.triggered);
        u8(i.pointer.active);
        u32(std::bit_cast<std::uint32_t>(i.pointer.x));
        u32(std::bit_cast<std::uint32_t>(i.pointer.y));
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
    void access(const LobbyAccess& value) {
        if (!value.valid())
            throw std::runtime_error("Invalid lobby access");
        u16(value.unlockedCharacters.size());
        for (auto id : value.unlockedCharacters)
            u16(id);
        // New-run availability is a subset of unlocked IDs. A bit per ID
        // keeps the maximum four-seat lobby within maxMessageSize.
        for (std::size_t i = 0; i < value.unlockedCharacters.size(); i += 8) {
            std::uint8_t available = 0;
            for (unsigned bit = 0; bit < 8 && i + bit < value.unlockedCharacters.size(); ++bit)
                if (value.allowsCharacter(value.unlockedCharacters[i + bit]))
                    available |= 1u << bit;
            u8(available);
        }
        u8(value.rules.size());
        for (auto rule : value.rules) {
            u16(rule.id);
            u16(rule.version);
        }
    }
};

class Reader {
    std::span<const std::uint8_t> bytes;
    std::size_t cursor = 0;
    const std::uint8_t* take(std::size_t size) {
        if (size > bytes.size() - cursor)
            throw std::runtime_error("Truncated protocol message");
        const auto* value = bytes.data() + cursor;
        cursor += size;
        return value;
    }

  public:
    explicit Reader(std::span<const std::uint8_t> b) : bytes(b) {}
    std::uint8_t u8() {
        if (cursor >= bytes.size())
            throw std::runtime_error("Truncated protocol message");
        return bytes[cursor++];
    }
    std::uint16_t u16() {
        const auto* value = take(sizeof(std::uint16_t));
        return static_cast<std::uint16_t>((value[0] << 8) | value[1]);
    }
    std::uint32_t u32() {
        const auto* value = take(sizeof(std::uint32_t));
        return (static_cast<std::uint32_t>(value[0]) << 24) |
               (static_cast<std::uint32_t>(value[1]) << 16) |
               (static_cast<std::uint32_t>(value[2]) << 8) | value[3];
    }
    std::uint64_t u64() {
        auto a = u32();
        return (static_cast<std::uint64_t>(a) << 32) | u32();
    }
    // The caller must keep the packet alive while using this bounded view.
    std::string_view stringView() {
        auto size = u16();
        if (size > 1024 || size > bytes.size() - cursor)
            throw std::runtime_error("Invalid protocol string");
        std::string_view out(reinterpret_cast<const char*>(bytes.data() + cursor), size);
        cursor += size;
        return out;
    }
    std::string string() {
        return std::string(stringView());
    }
    InputFrame input() {
        InputFrame out;
        for (auto& n : out.values)
            n = u16();
        out.triggered = u16();
        const auto active = u8();
        out.pointer = {active != 0, std::bit_cast<float>(u32()), std::bit_cast<float>(u32())};
        if (active > 1 || !validPointer(out.pointer))
            throw std::runtime_error("Invalid input pointer");
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
    LobbyAccess access() {
        LobbyAccess value;
        const auto characters = u16();
        if (characters > 256)
            throw std::runtime_error("Too many lobby characters");
        for (unsigned i = 0; i < characters; ++i)
            value.unlockedCharacters.push_back(u16());
        for (unsigned i = 0; i < characters; i += 8) {
            const auto available = u8();
            if (characters - i < 8 && (available >> (characters - i)))
                throw std::runtime_error("Invalid lobby availability bits");
            for (unsigned bit = 0; bit < 8 && i + bit < characters; ++bit)
                if (available & (1u << bit))
                    value.characters.push_back(value.unlockedCharacters[i + bit]);
        }
        const auto rules = u8();
        if (rules > 64)
            throw std::runtime_error("Too many lobby rules");
        for (unsigned i = 0; i < rules; ++i) {
            const auto id = u16();
            value.rules.push_back({id, u16()});
        }
        if (!value.valid())
            throw std::runtime_error("Invalid lobby access");
        return value;
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

#include "lan_session.h"
#include "progression.h"
#include "state_compression.h"
#include "test_support.h"
#include <windows.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <functional>
#include <memory>
using namespace isaac::lan;
namespace {
template <class F> void until(F f) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
    while (!f()) {
        require(std::chrono::steady_clock::now() < deadline, "Test timed out");
        Sleep(0);
    }
}
struct Group {
    std::array<std::unique_ptr<Session>, 4> peers;
    unsigned count;
    explicit Group(unsigned n) : count(n) {
        for (unsigned i = 0; i < n; ++i)
            peers[i] = std::make_unique<Session>();
        require(peers[0]->host(0, "state-test", "host-mods"), "Host failed");
        for (unsigned i = 1; i < n; ++i)
            require(
                peers[i]->join("127.0.0.1", peers[0]->port(), "state-test", {}, "cosmetic-mods"),
                "Join failed");
        until([&] {
            poll();
            return peers[0]->players() == n && peers[n - 1]->players() == n;
        });
        Start start;
        start.seed = "YV039KQF";
        require(peers[0]->start(start), "Start failed");
        until([&] {
            poll();
            return std::all_of(peers.begin(), peers.begin() + n,
                               [](const auto& p) { return p->phase() == Phase::running; });
        });
    }
    void poll() {
        for (unsigned i = 0; i < count; ++i)
            if (peers[i]) {
                peers[i]->poll();
                if (peers[i]->phase() == Phase::failed)
                    throw std::runtime_error(peers[i]->error());
            }
    }
    void ready() {
        for (unsigned i = 0; i < count; ++i)
            require(peers[i]->ready(), "Ready failed");
        poll();
    }
    Frame step(unsigned sequence) {
        require(peers[0]->submit(sequence, {}), "Host submit failed");
        std::optional<Frame> frame;
        until([&] {
            poll();
            frame = peers[0]->take();
            return frame.has_value();
        });
        peers[0]->completed(frame->tick);
        return *frame;
    }
    void publish(unsigned tick, std::size_t length = 6507) {
        WorldState state;
        state.tick = tick;
        state.connected = peers[0]->connectedMask();
        state.inputSequences = peers[0]->inputSequences();
        state.bytes.resize(length);
        for (std::size_t i = 0; i < length; ++i)
            state.bytes[i] = static_cast<unsigned char>(i + tick);
        for (unsigned slot = 1; slot < count; ++slot)
            require(peers[0]->publish(slot, state), "Publish failed");
    }
};
void codec() {
    StateCompression compression;
    std::vector<std::uint8_t> plain(512000, 42);
    const auto compact = compression.compress(plain);
    require(compact.size() < plain.size() / 10 && compression.expand(compact) == plain,
            "Independent snapshot compression failed");
    auto corrupt = compact;
    corrupt[1] = 0xff;
    bool tooLarge = false;
    try {
        compression.expand(corrupt);
    } catch (const std::exception&) {
        tooLarge = true;
    }
    require(tooLarge, "Compressed state could allocate an unbounded replica");
    Writer w(Message::world);
    w.u32(0x12345678);
    w.blob(std::vector<std::uint8_t>(409, 0x55));
    for (unsigned length = 1; length < w.bytes.size(); ++length) {
        bool rejected = false;
        try {
            Reader r(std::span(w.bytes).first(length));
            r.u8();
            r.u32();
            r.blob();
            r.finish();
        } catch (const std::exception&) {
            rejected = true;
        }
        require(rejected, "Truncated state packet accepted");
    }
    Reader r(w.bytes);
    r.u8();
    require(r.u32() == 0x12345678 && r.blob().size() == 409, "State codec failed");
    r.finish();
    std::puts("PASS bounded state codec rejects truncated packets");
}
void inputsAndStates(unsigned n) {
    Group g(n);
    until([&] {
        g.poll();
        return g.peers[0]->latency()[n - 1] >= 0 && g.peers[n - 1]->latency()[n - 1] >= 0;
    });
    for (unsigned slot = 1; slot < n; ++slot)
        require(g.peers[0]->latency()[slot] >= 0, "Peer round-trip measurement missing");
    require(g.peers[0]->modsDiffer(), "Different Mods did not remain an advisory");
    require(g.peers[0]->ready(), "Host ready failed");
    require(g.peers[0]->submit(0, {}), "Initial host sample failed");
    require(!g.peers[0]->take(), "Host started before guests loaded");
    for (unsigned i = 1; i < n; ++i)
        require(g.peers[i]->ready(), "Guest ready failed");
    std::optional<Frame> first;
    until([&] {
        g.poll();
        first = g.peers[0]->take();
        return first.has_value();
    });
    require(first->tick == 0, "Loading manufactured simulation frames");
    g.peers[0]->completed(0);
    InputFrame press;
    press.values[0] = 50000;
    press.triggered = 1u << 12;
    require(g.peers[1]->submit(0, press), "Guest press failed");
    require(g.peers[1]->submit(1, {}), "Guest release failed");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 1;
    });
    const auto frame = g.step(1);
    require(frame.inputs[1].values[0] == 0 && frame.inputs[1].triggered == (1u << 12),
            "Latest input lost short button edge or retained stale movement");
    require(g.step(2).inputs[1].triggered == 0, "Button edge repeated");
    for (unsigned t = 3; t < 180; ++t) {
        require(g.step(t).tick == t, "Host stalled waiting for a guest input");
        g.publish(t);
        g.poll();
    }
    std::array<std::uint32_t, 4> last{};
    until([&] {
        g.poll();
        bool done = true;
        for (unsigned i = 1; i < n; ++i) {
            if (auto state = g.peers[i]->takeState()) {
                require(state->connected == (1u << n) - 1 && state->inputSequences[1] == 1,
                        "Authority metadata incorrect");
                for (std::size_t b = 0; b < state->bytes.size(); ++b)
                    require(state->bytes[b] == static_cast<unsigned char>(b + state->tick),
                            "State chunks corrupted");
                last[i] = state->tick;
                g.peers[i]->applied(state->tick);
            }
            done = done && last[i] == 179;
        }
        return done;
    });
    g.poll();
    require(g.peers[1]->verifiedTick() == 179, "State acknowledgement missing");
    g.peers[0]->finish();
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::closed;
    });
    std::printf("PASS %u players: host never waits for remote ticks; latest states coalesce; edges "
                "arrive once; shared finish\n",
                n);
}
void floorRejoin() {
    Group g(2);
    g.ready();
    g.step(0);
    const auto identity = g.peers[1]->identity();
    g.peers[1]->close();
    g.poll();
    require(g.step(1).connected == 1, "Departure did not remove guest from active roster");
    g.peers[1] = std::make_unique<Session>();
    require(g.peers[1]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, "other-mods"),
            "Returning connection failed");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::waiting;
    });
    Start checkpoint = g.peers[0]->settings();
    checkpoint.snapshot.resize(65537, 0x47);
    require(g.peers[0]->checkpoint(checkpoint, 2), "Floor checkpoint failed");
    for (unsigned i = 2; i < 30; ++i)
        require(g.step(i).connected == 1, "Loading guest entered combat early");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::running;
    });
    require(g.peers[1]->settings().snapshot == checkpoint.snapshot, "Floor checkpoint corrupt");
    require(g.peers[1]->ready(), "Restored engine ready failed");
    until([&] {
        g.poll();
        return g.peers[0]->connectedMask() == 3;
    });
    require(g.step(30).connected == 3, "Ready guest was not restored");
    g.publish(30);
    std::optional<WorldState> value;
    until([&] {
        g.poll();
        value = g.peers[1]->takeState();
        return value.has_value();
    });
    require(value->tick == 30, "Returning client replayed history instead of current state");
    g.peers[1]->applied(value->tick);
    g.poll();
    std::puts("PASS rejoin loads current checkpoint then latest state; host continues during "
              "loading; no input-history replay");
}
void stageEvents() {
    Group g(2);
    g.ready();
    g.step(0);
    g.publish(0, 40000);
    // Supersede a view that may be only partly queued, then publish the new
    // floor. The event must survive state coalescing and preserve native args.
    Stage stage{1, 1, 0, 0, false, {}, {}};
    for (unsigned i = 0; i < stage.seeds.size(); ++i)
        stage.seeds[i] = 0x12340000 + i;
    require(g.peers[0]->beginStage(stage), "Stage broadcast failed");
    std::optional<Stage> received;
    until([&] {
        g.poll();
        received = g.peers[1]->takeStage();
        return received.has_value();
    });
    require(*received == stage, "Native floor event changed arguments");
    require(!g.peers[1]->takeState(), "Old floor view survived its begin event");
    g.step(1);
    g.publish(1);
    std::optional<WorldState> world;
    until([&] {
        g.poll();
        world = g.peers[1]->takeState();
        return world.has_value();
    });
    require(world->tick == 1, "Floor event damaged subsequent world transfer");
    const auto identity = g.peers[1]->identity();
    g.peers[1]->abort("isolated connection loss");
    until([&] {
        g.peers[0]->poll();
        return g.peers[0]->connectedMask() == 1;
    });
    require(g.peers[1]->reconnect(), "Automatic return connection failed");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::waiting;
    });
    require(g.peers[1]->identity() == identity, "Automatic return lost player identity");
    require(g.peers[0]->beginStage({2, 2, 0, 0, false, {}, {}}), "Second stage broadcast failed");
    g.poll();
    require(!g.peers[1]->takeStage() && g.peers[1]->phase() == Phase::waiting,
            "Waiting player entered an online floor animation");
    std::puts("PASS native floor begin precedes new state; automatic return retains identity until "
              "a checkpoint is supplied");
}
void stageDuringRejoin() {
    Group g(2);
    g.ready();
    g.step(0);
    const auto identity = g.peers[1]->identity();
    g.peers[1]->close();
    g.poll();
    g.step(1);
    g.peers[1] = std::make_unique<Session>();
    require(g.peers[1]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity),
            "Returning connection failed");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::waiting;
    });
    Start saved = g.peers[0]->settings();
    saved.snapshot.resize(65537, 0x47);
    require(g.peers[0]->checkpoint(saved, 2), "Current-floor checkpoint failed");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::running;
    });
    require(g.peers[0]->beginStage({1, 1, 0, 0, false, {}, {}}),
            "First loading floor event failed");
    const Stage last{2, 2, 0, 0, false, {}, {}};
    require(g.peers[0]->beginStage(last), "Second loading floor event failed");
    g.poll();
    require(!g.peers[1]->takeStage(), "Native event reached an unprepared engine");
    require(g.peers[1]->ready(), "Returning readiness failed");
    std::optional<Stage> received;
    until([&] {
        g.poll();
        received = g.peers[1]->takeStage();
        return received.has_value();
    });
    require(*received == last, "Slow loader missed the latest floor event");
    std::puts(
        "PASS host floor changes during guest loading are delivered before the first live view");
}
void rewindTransaction() {
    Group g(2);
    g.ready();
    g.step(0);
    g.publish(0, 40000);
    Stage value{1, 1, 0, 12, false, {}, {}};
    value.rewind.resize(300001);
    unsigned random = 17;
    for (auto& b : value.rewind) {
        random = random * 1664525 + 1013904223;
        b = random >> 24;
    }
    require(g.peers[0]->beginStage(value), "Rewind transfer failed");
    g.step(1);
    g.publish(1);
    std::optional<Stage> received;
    until([&] {
        g.poll();
        received = g.peers[1]->takeStage();
        return received.has_value();
    });
    require(*received == value, "Chunked native rewind checkpoint changed");
    std::optional<WorldState> world;
    until([&] {
        g.poll();
        world = g.peers[1]->takeState();
        return world.has_value();
    });
    require(world->tick == 1, "Rewind did not precede its new world state");
    std::puts("PASS large native rewind is reliable and precedes subsequent world views");
}
void progression() {
    Progress local, shared, current;
    local.achievements[7] = 1;
    shared.achievements[9] = 1;
    current = shared;
    current.achievements[11] = 1;
    local.counters[0] = 12;
    shared.counters[0] = 1000;
    current.counters[0] = 1003;
    const auto merged = mergeProgress(local, shared, current);
    require(merged.achievements[7] && !merged.achievements[9] && merged.achievements[11] &&
                merged.counters[0] == 15,
            "Local progression isolation failed");
    std::puts("PASS local progression remains isolated");
}
void rKeyTransaction() {
    Group g(2);
    g.ready();
    g.step(0);
    Stage value;
    value.epoch = 1;
    value.level = 1;
    value.rKey = true;
    for (unsigned i = 0; i < value.seeds.size(); ++i)
        value.seeds[i] = 0x12345600 + i;
    require(g.peers[0]->beginStage(value), "R Key event failed");
    g.step(1);
    g.publish(1);
    std::optional<Stage> event;
    until([&] {
        g.poll();
        event = g.peers[1]->takeStage();
        return event.has_value();
    });
    require(*event == value, "Native R Key mode or pre-restart Seeds changed");
    std::optional<WorldState> world;
    until([&] {
        g.poll();
        world = g.peers[1]->takeState();
        return world.has_value();
    });
    require(world->tick == 1, "R Key event did not precede its new floor state");
    std::puts("PASS native R Key event preserves pre-restart seeds and precedes world state");
}
void roomCommands() {
    Group g(2);
    g.ready();
    g.step(0);
    RoomRequest request{1, 0, 0, 0, 84, 71, true};
    require(!g.peers[0]->requestRoom(request), "Host submitted a remote player command");
    require(g.peers[1]->requestRoom(request), "Guest native room command failed");
    std::optional<RoomRequest> received;
    until([&] {
        g.poll();
        received = g.peers[0]->takeRoomRequests()[1];
        return received.has_value();
    });
    require(*received == request, "Native room command changed source or animation");
    require(!g.peers[0]->takeRoomRequests()[1], "Room command repeated after consumption");
    std::puts("PASS native Mod room requests retain source and owner; commands consume once");
}
void inputRooms() {
    Group g(2);
    g.ready();
    g.step(0);
    const InputRoom source{3, 84, 1}, destination{3, 71, 1};
    InputFrame press;
    press.values[2] = 65535;
    press.triggered = 1u << 6;
    require(g.peers[1]->submit(0, press, source), "Source room input failed");
    require(g.peers[1]->submit(1, {}, source), "Source release failed");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 1;
    });
    auto frame = g.step(1);
    require(frame.inputRooms[1] == source && frame.inputs[1].triggered == press.triggered,
            "Source input lost room identity or short press");
    require(g.peers[1]->submit(2, press, source), "Queued source press failed");
    require(g.peers[1]->submit(3, {}, destination), "Destination input failed");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 3;
    });
    frame = g.step(2);
    require(frame.inputRooms[1] == destination && frame.inputs[1].triggered == 0,
            "Source room edge leaked into the destination");
    std::puts("PASS input room identity and edges stay within room boundaries");
}
void compressionLimits() {
    StateCompression compression;
    rejects([&] { compression.compress({}); }, "Empty state accepted");
    rejects([&] { compression.compress(std::vector<std::uint8_t>(maxWorldSize + 1)); },
            "Oversized state accepted");
    for (const auto& plain :
         {std::vector<std::uint8_t>{0xff}, std::vector<std::uint8_t>(maxWorldSize, 42)})
        require(compression.expand(compression.compress(plain)) == plain,
                "Compression boundary round trip failed");
    Writer raw(Message::world);
    raw.bytes.clear();
    raw.u8(0);
    raw.u32(3);
    raw.u8(0);
    raw.u8(0x80);
    raw.u8(0xff);
    require(compression.expand(raw.bytes) == std::vector<std::uint8_t>({0, 0x80, 0xff}),
            "Plain mode failed");
    for (std::size_t size = 0; size < raw.bytes.size(); ++size)
        rejects([&] { compression.expand(std::span(raw.bytes).first(size)); },
                "Truncated plain state accepted");
    auto invalid = raw.bytes;
    invalid.push_back(0);
    rejects([&] { compression.expand(invalid); }, "Trailing plain state data accepted");
    invalid = raw.bytes;
    invalid[0] = 2;
    rejects([&] { compression.expand(invalid); }, "Unknown compression mode accepted");
    invalid = raw.bytes;
    std::fill(invalid.begin() + 1, invalid.begin() + 5, 0);
    rejects([&] { compression.expand(invalid); }, "Zero-length state accepted");
    invalid = raw.bytes;
    invalid[0] = 1;
    rejects([&] { compression.expand(invalid); }, "Invalid compressed payload accepted");
    const auto compressed = compression.compress(std::vector<std::uint8_t>(10000, 42));
    invalid = compressed;
    invalid.pop_back();
    rejects([&] { compression.expand(invalid); }, "Truncated compressed payload accepted");
    invalid = compressed;
    invalid[4] ^= 1;
    rejects([&] { compression.expand(invalid); }, "Incorrect expanded size accepted");
}
void lobby() {
    Session host, guest;
    require(!host.ready() && !host.submit(0, {}) && !host.command(Command::pause),
            "Idle session accepted gameplay");
    require(host.host(0, "test", "mods"), "Host failed");
    Start start;
    start.seed = "YV039KQF";
    require(!host.start(start), "Single-player lobby started");
    require(guest.join("127.0.0.1", host.port(), "test", {}, "mods"), "Join failed");
    auto poll = [&] {
        host.poll();
        guest.poll();
    };
    until([&] {
        poll();
        return host.players() == 2 && guest.phase() == Phase::lobby;
    });
    require(!host.modsDiffer() && !guest.modsDiffer(), "Identical Mods reported different");
    require(!guest.start(start), "Guest started session");
    require(host.choose({1, true}) && guest.choose({2, false}), "Choice failed");
    until([&] {
        poll();
        return host.choices()[1].character == 2;
    });
    start.characters = {1, 2, 0, 0};
    require(!host.start(start), "Unready guest started");
    require(guest.choose({2, true}), "Guest ready choice failed");
    until([&] {
        poll();
        return host.choices()[1].ready && guest.choices()[0].ready;
    });
    start.seed = "short";
    require(!host.start(start), "Invalid seed accepted");
    start.seed = "YV039KQF";
    start.difficulty = 4;
    require(!host.start(start), "Invalid difficulty accepted");
    start.difficulty = 0;
    start.characters[1] = 3;
    require(!host.start(start), "Mismatched character accepted");
    start.characters[1] = 2;
    require(host.start(start), "Ready lobby did not start");
    until([&] {
        poll();
        return guest.phase() == Phase::running;
    });
    require(guest.settings().characters == start.characters && guest.settings().seed == start.seed,
            "Start settings changed");
    require(!host.choose({}) && !guest.choose({}), "Running session changed lobby choice");
}
void handshake() {
    Session host, rejected;
    require(host.host(0, "supported"), "Host failed");
    require(rejected.join("127.0.0.1", host.port(), "incompatible"), "Connection failed");
    until([&] {
        host.poll();
        rejected.poll();
        return rejected.phase() == Phase::failed;
    });
    require(host.phase() == Phase::lobby && host.players() == 1 && !rejected.error().empty(),
            "Rejected handshake damaged host");
    Session guest;
    require(guest.join("127.0.0.1", host.port(), "supported"), "Valid join after rejection failed");
    until([&] {
        host.poll();
        guest.poll();
        return host.players() == 2 && guest.phase() == Phase::lobby;
    });
    Session badAddress, badIdentity;
    require(!badAddress.join("invalid", host.port(), "supported"), "Invalid IPv4 accepted");
    require(!badIdentity.join("127.0.0.1", host.port(), "supported", "not-an-identity"),
            "Invalid identity accepted");
}
void commands() {
    Group g(2);
    g.ready();
    g.step(0);
    require(!g.peers[1]->command(Command::saveExit) && !g.peers[0]->command(Command::leave) &&
                !g.peers[0]->command(Command::none),
            "Unauthorized command accepted");
    for (Command command : {Command::pause, Command::resume}) {
        require(g.peers[1]->command(command), "Guest command failed");
        // Poll until the command is consumed, rather than assuming one socket
        // poll is enough on every Windows runner.
        unsigned sequence = g.peers[0]->inputSequences()[0] + 1;
        Frame frame;
        until([&] {
            g.poll();
            frame = g.step(sequence++);
            return frame.commands[1] == command;
        });
        require(g.step(sequence).commands[1] == Command::none, "Guest command repeated");
    }
    require(g.peers[0]->command(Command::saveExit), "Host save command failed");
    auto sequence = g.peers[0]->inputSequences()[0] + 1;
    require(g.step(sequence).commands[0] == Command::saveExit, "Host save command missing");
    require(g.step(sequence + 1).commands[0] == Command::none, "Host save command repeated");
    require(g.peers[1]->command(Command::leave), "Guest departure failed");
    until([&] {
        g.peers[0]->poll();
        return g.peers[0]->connectedMask() == 1;
    });
    require(g.step(sequence + 2).connected == 1, "Departed guest stayed active");
}
void publicationLimits() {
    Group g(2);
    g.ready();
    g.step(0);
    require(!g.peers[0]->submit(0, {}) && !g.peers[0]->submit(2, {}),
            "Duplicate or skipped input sequence accepted");
    WorldState state;
    state.bytes = {42};
    require(!g.peers[0]->publish(0, state) && !g.peers[0]->publish(2, state) &&
                !g.peers[1]->publish(1, state),
            "Invalid publication owner or slot accepted");
    state.tick = 1;
    require(!g.peers[0]->publish(1, state), "Future world tick accepted");
    state.tick = 0;
    state.bytes.clear();
    require(!g.peers[0]->publish(1, state), "Empty world state accepted");
    state.bytes.resize(maxWorldSize + 1);
    require(!g.peers[0]->publish(1, state), "Oversized world state accepted");
    state.bytes = {42};
    require(g.peers[0]->publish(1, state), "Valid world state rejected after invalid attempts");
    std::optional<WorldState> received;
    until([&] {
        g.poll();
        received = g.peers[1]->takeState();
        return received.has_value();
    });
    require(received->bytes == state.bytes && received->tick == 0, "Valid publication damaged");
}
void integrations() {
    Group g(3);
    require(g.peers[0]->runId().size() == 32 && g.peers[0]->runId() == g.peers[1]->runId() &&
                g.peers[0]->runId() == g.peers[2]->runId(),
            "Run identity differs between peers");
    g.ready();
    g.step(0);
    require(!g.peers[1]->sendIntegration(2, "forged-peer") && !g.peers[1]->sendIntegration(0, {}) &&
                !g.peers[1]->sendIntegration(0, std::string(maxIntegrationSize + 1, 'x')),
            "Invalid integration destination or limit accepted");
    for (unsigned i = 0; i < 8; ++i)
        require(g.peers[1]->sendIntegration(0, std::string("request-") + std::to_string(i)),
                "Action send failed");
    require(g.peers[2]->sendIntegration(0, "other-owner"), "Second owner action failed");
    unsigned received = 0;
    until([&] {
        g.poll();
        while (auto packet = g.peers[0]->takeIntegration()) {
            if (packet->sender == 1)
                require(packet->bytes == std::string("request-") + std::to_string(received++),
                        "Reliable requests were merged or reordered");
            else
                require(packet->sender == 2 && packet->bytes == "other-owner",
                        "Sender identity not transport-assigned");
        }
        return received == 8;
    });
    require(g.peers[0]->sendIntegration(1, "result"), "Host result failed");
    std::optional<IntegrationMessage> result;
    until([&] {
        g.poll();
        result = g.peers[1]->takeIntegration();
        return result.has_value();
    });
    require(result->sender == 0 && result->bytes == "result" && !g.peers[2]->takeIntegration(),
            "Result leaked to a different recipient");
    for (unsigned i = 0; i < maxIntegrationQueue; ++i)
        require(g.peers[0]->sendIntegration(0, "local"), "Local action queue filled prematurely");
    require(!g.peers[0]->sendIntegration(0, "overflow"), "Local action queue was unbounded");
    for (unsigned i = 0; i < maxIntegrationQueue; ++i)
        require(g.peers[0]->takeIntegration().has_value(), "Local action lost");
    Stage stage;
    stage.epoch = 3;
    stage.level = 2;
    require(g.peers[0]->beginStage(stage), "Epoch event failed");
    until([&] {
        g.poll();
        return g.peers[1]->worldEpoch() == 3 && g.peers[2]->worldEpoch() == 3;
    });
    require(g.peers[0]->worldEpoch() == 3, "Authority epoch not retained");
    const auto runId = g.peers[0]->runId();
    const auto identity = g.peers[2]->identity();
    g.peers[2]->close();
    until([&] {
        g.peers[0]->poll();
        return g.peers[0]->connectedMask() == 3;
    });
    g.peers[2] = std::make_unique<Session>();
    require(g.peers[2]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity),
            "Integration rejoin failed");
    until([&] {
        g.poll();
        return g.peers[2]->phase() == Phase::waiting;
    });
    Start checkpoint = g.peers[0]->settings();
    checkpoint.snapshot = {1, 2, 3};
    require(g.peers[0]->checkpoint(checkpoint, 1), "Integration checkpoint failed");
    until([&] {
        g.poll();
        return g.peers[2]->phase() == Phase::running;
    });
    require(g.peers[2]->runId() == runId && g.peers[2]->worldEpoch() == 3,
            "Rejoin lost run identity or world epoch");
}
void hostDisconnect() {
    Group g(2);
    g.ready();
    g.step(0);
    g.peers[0]->close();
    until([&] {
        g.peers[1]->poll();
        return g.peers[1]->phase() == Phase::failed;
    });
    require(!g.peers[1]->error().empty() && !g.peers[1]->take(),
            "Host departure did not end guest simulation");
}
} // namespace
int main(int argc, char** argv) {
    const auto result = runTests(argc, argv,
                                 {{"codec", codec},
                                  {"compression-limits", compressionLimits},
                                  {"inputs-2", [] { inputsAndStates(2); }},
                                  {"inputs-3", [] { inputsAndStates(3); }},
                                  {"inputs-4", [] { inputsAndStates(4); }},
                                  {"floor-rejoin", floorRejoin},
                                  {"stage-events", stageEvents},
                                  {"stage-during-rejoin", stageDuringRejoin},
                                  {"rewind", rewindTransaction},
                                  {"progression", progression},
                                  {"r-key", rKeyTransaction},
                                  {"room-commands", roomCommands},
                                  {"input-rooms", inputRooms},
                                  {"lobby", lobby},
                                  {"handshake", handshake},
                                  {"commands", commands},
                                  {"publication-limits", publicationLimits},
                                  {"integrations", integrations},
                                  {"host-disconnect", hostDisconnect}});
    if (!result)
        std::puts("ALL STATE TRANSPORT TESTS PASSED");
    return result;
}

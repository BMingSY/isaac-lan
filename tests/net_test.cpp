#include "net/session.h"
#include "net/datagram_protocol.h"
#include <enet/enet.h>
#include "compat/challenges/catalog.h"
#include "runtime/progression.h"
#include "net/compression.h"
#include "net/peer.h"
#include "net/wire_codec.h"
#include "test_support.h"
#include "udp_relay.h"
#include <winsock2.h>
#include <windows.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <functional>
#include <memory>
#include <psapi.h>
#include <random>
#include <source_location>
using namespace isaac::lan;
namespace {
using TestSession = Session;
LobbyAccess testAccess() {
    return {{0, 1, 2, 3, 7, 23}, {{1001, 2}, {1001, 3}, {1002, 1}}, {0, 1, 2, 3, 7, 23}};
}
template <class F>
void until(F f, const std::source_location location = std::source_location::current()) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(8);
    while (!f()) {
        if (std::chrono::steady_clock::now() >= deadline)
            throw std::runtime_error("Test timed out at line " + std::to_string(location.line()));
        Sleep(0);
    }
}
struct Group {
    std::array<std::unique_ptr<TestSession>, 4> peers;
    std::unique_ptr<UdpRelay> relay;
    unsigned count;
    explicit Group(unsigned n, std::uint8_t difficulty = 0, const char* address = "127.0.0.1",
                   RunRules rules = {}, std::array<std::uint16_t, maxPlayers> characters = {},
                   bool relayed = false)
        : count(n) {
        for (unsigned i = 0; i < n; ++i)
            peers[i] = std::make_unique<TestSession>();
        require(peers[0]->host(0, "state-test", "host-mods", testAccess()), "Host failed");
        if (relayed)
            relay = std::make_unique<UdpRelay>(peers[0]->port());
        for (unsigned i = 1; i < n; ++i) {
            require(peers[i]->join(address, relay ? relay->port : peers[0]->port(), "state-test",
                                   {}, "cosmetic-mods", testAccess()),
                    "Join failed");
            // Seat assignment follows accepted connections, not thread start order.
            until([&] {
                poll();
                return peers[i]->phase() == Phase::lobby;
            });
            require(peers[i]->slot() == i, "Connection received the wrong seat");
        }
        until([&] {
            poll();
            return std::all_of(peers.begin(), peers.begin() + n,
                               [&](const auto& peer) { return peer->players() == n; });
        });
        Start start;
        start.seed = "YV039KQF";
        start.difficulty = difficulty;
        start.rules = rules;
        start.characters = characters;
        if (rules.id) {
            require(peers[0]->configureRules(rules), "Rule configuration failed");
            until([&] {
                poll();
                return std::all_of(peers.begin(), peers.begin() + n,
                                   [&](const auto& peer) { return peer->rules() == rules; });
            });
            if (rules.character != RunRules{}.character)
                start.characters.fill(rules.character);
            for (unsigned i = 0; i < n; ++i)
                require(peers[i]->choose({start.characters[i], true}), "Rule choice failed");
            until([&] {
                poll();
                for (unsigned i = 0; i < n; ++i)
                    if (!peers[0]->choices()[i].ready)
                        return false;
                return true;
            });
        }
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
void greedSettings() {
    for (std::uint8_t difficulty : {2, 3}) {
        Group g(2, difficulty);
        for (unsigned i = 0; i < g.count; ++i)
            require(g.peers[i]->settings().difficulty == difficulty,
                    "Greed lobby start lost its difficulty");
        g.ready();
        g.step(0);
        Stage first{1, 2, 0, 0, false, {}, {}};
        require(g.peers[0]->beginStage(first), "Greed first floor event failed");
        std::optional<Stage> event;
        until([&] {
            g.poll();
            event = g.peers[1]->takeStage();
            return event.has_value();
        });
        require(*event == first, "Greed first floor event changed");
        // The native client is still loading floor 2 when the host prepares
        // floor 7. Polling and reading world views must leave its event intact
        // until runtime can consume it with a ready native roster.
        Stage terminal{2, 7, 0, 0, true, {}, {}};
        terminal.seeds.fill(0x12345678);
        require(g.peers[0]->beginStage(terminal), "Greed consecutive floor event failed");
        g.step(1);
        g.publish(1);
        std::optional<WorldState> world;
        until([&] {
            g.poll();
            world = g.peers[1]->takeState();
            return world.has_value();
        });
        require(g.peers[1]->worldEpoch() == terminal.epoch,
                "Delayed Greed floor event lost its epoch");
        event = g.peers[1]->takeStage();
        require(event && *event == terminal && !g.peers[1]->takeStage(),
                "Delayed Greed floor event was lost or replayed during loading");
        const auto identity = g.peers[1]->identity();
        g.peers[1]->close();
        until([&] {
            g.poll();
            return g.peers[0]->connectedMask() == 1;
        });
        g.step(2);
        g.peers[1] = std::make_unique<TestSession>();
        require(g.peers[1]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, {},
                                 testAccess()),
                "Greed guest could not rejoin");
        until([&] {
            g.poll();
            return g.peers[1]->phase() == Phase::waiting;
        });
        Start checkpoint = g.peers[0]->settings();
        checkpoint.snapshot.assign(4097, difficulty);
        require(g.peers[0]->checkpoint(checkpoint, 3), "Greed checkpoint failed");
        until([&] {
            g.poll();
            return g.peers[1]->phase() == Phase::running;
        });
        require(g.peers[1]->settings().difficulty == difficulty &&
                    g.peers[1]->settings().snapshot == checkpoint.snapshot,
                "Greed rejoin lost its mode or current-floor checkpoint");
    }
}
void codec() {
    Writer strings(Message::world);
    const std::string_view binary("a\0b", 3);
    strings.string(binary);
    require(strings.bytes == std::vector<std::uint8_t>(
                                 {static_cast<std::uint8_t>(Message::world), 0, 3, 'a', 0, 'b'}),
            "Borrowed string writer changed protocol bytes");
    Reader borrowed(strings.bytes), owned(strings.bytes);
    borrowed.u8();
    owned.u8();
    require(borrowed.stringView() == binary && owned.string() == binary,
            "Borrowed or owned string reader changed bytes");
    borrowed.finish();
    owned.finish();
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
void udpLossRecoveryImpl(bool large) {
    Group g(2, 0, "127.0.0.1", {}, {}, true);
    g.ready();
    g.step(0);
    std::mt19937 random(103);
    std::vector<std::uint8_t> data(large ? 100000 : 32000);
    const unsigned changingBytes = large ? 88000 : 2600;
    for (auto& byte : data)
        byte = static_cast<std::uint8_t>(random());
    const auto dependency = [&](unsigned tick) {
        std::vector<std::uint8_t> bytes(data.begin(), data.begin() + 4000);
        // Adjacent revisions while the previous reliable packet is in flight.
        bytes[0] = static_cast<std::uint8_t>(tick / 30);
        bytes[1] = static_cast<std::uint8_t>(tick % 30 == 0);
        return bytes;
    };
    if (large) {
        // Establish the shared baseline before the busy room starts changing
        // ~88 KiB per update. The smaller fixture also covers lossy bootstrap.
        WorldState initial;
        initial.connected = 3;
        initial.bytes = data;
        initial.stable = dependency(0);
        require(g.peers[0]->publish(1, initial), "Large baseline rejected");
        bool applied = false;
        until([&] {
            g.poll();
            if (auto arrived = g.peers[1]->takeState()) {
                require(arrived->bytes == data, "Large baseline changed bytes");
                g.peers[1]->applied(arrived->tick);
                applied = true;
            }
            return applied && g.peers[0]->resources().inFlightStates == 0;
        });
    }
    g.relay->impaired.store(true);
    constexpr auto actionBit = 1u << isaac::input::action::item;
    unsigned actions = 0, received = 0, lastTick = 0, largestGap = 0;
    const auto collect = [&] {
        g.poll();
        if (auto arrived = g.peers[1]->takeState()) {
            require(arrived->tick > lastTick && arrived->bytes.size() == data.size() &&
                        arrived->bytes[0] == (arrived->tick & 255),
                    "UDP duplicate/reordering regressed or corrupted a snapshot");
            require(arrived->stable == dependency(arrived->tick),
                    "Lost/reordered dependency changed an authoritative view");
            for (unsigned i = 1; i < data.size(); ++i)
                require(arrived->bytes[i] ==
                            (data[i] ^ (arrived->tick > 60 && i < changingBytes
                                            ? static_cast<std::uint8_t>(arrived->tick)
                                            : 0)),
                        "Fragmented prefix recovery changed world bytes");
            largestGap = std::max(largestGap, arrived->tick - lastTick);
            lastTick = arrived->tick;
            ++received;
            g.peers[1]->applied(arrived->tick);
        }
    };
    const auto publish = [&](unsigned sequence) {
        auto frame = g.step(sequence);
        actions += (frame.inputs[1].triggered & actionBit) != 0;
        WorldState state;
        state.tick = frame.tick;
        state.connected = 3;
        state.inputSequences = g.peers[0]->inputSequences();
        state.bytes = data;
        state.stable = dependency(sequence);
        // A busy room changes enough data to fragment even prefix-compressed
        // frames. Exercise transitions between small and multi-datagram views.
        if (sequence > 60)
            for (unsigned i = 1; i < changingBytes; ++i)
                state.bytes[i] ^= static_cast<std::uint8_t>(sequence);
        state.bytes[0] = sequence;
        require(g.peers[0]->publish(1, state), "Impaired world rejected");
    };
    for (unsigned sequence = 1; sequence <= 180; ++sequence) {
        const auto began = std::chrono::steady_clock::now();
        InputFrame input;
        input.values[isaac::input::action::moveRight] = sequence < 150 ? maxInputValue : 0;
        if (sequence <= 120 && sequence % 15 == 0)
            input.triggered = actionBit;
        require(g.peers[1]->submit(sequence - 1, input, InputRoom{0, 84, 0}),
                "Impaired input rejected");
        publish(sequence);
        do {
            collect();
            Sleep(1);
        } while (std::chrono::steady_clock::now() - began < std::chrono::milliseconds(33));
    }
    std::printf(
        "UDP observed received=%u last=%u largest_gap=%u actions=%u dropped=%u duplicates=%u\n",
        received, lastTick, largestGap, actions, g.relay->dropped.load(),
        g.relay->duplicated.load());
    const auto delivery = g.peers[0]->resources();
    std::printf("UDP states=%llu delta=%llu raw=%llu wire=%llu\n",
                static_cast<unsigned long long>(delivery.worldSnapshots),
                static_cast<unsigned long long>(delivery.deltaSnapshots),
                static_cast<unsigned long long>(delivery.rawWorldBytes),
                static_cast<unsigned long long>(delivery.wireWorldBytes));
    if (large) {
        require(received > 50 && lastTick > 165 && largestGap <= 15,
                "Large realtime views stalled despite recoverable datagram loss");
        // Keep impairing the link after the measurement window. The final
        // publication is still allowed to be lost; subsequent views must recover.
        unsigned sequence = 180;
        until([&] {
            publish(++sequence);
            collect();
            Sleep(33);
            return lastTick > 180;
        });
    } else
        require(received > 75 && lastTick > 165 && largestGap <= 12,
                "Lost fragments or baseline receipts stalled subsequent UDP snapshots");
    require(actions == 8, "Lost or duplicated a reliable one-shot action under UDP loss");
    require(g.relay->dropped > 20 && g.relay->duplicated > 20 && g.relay->maxBytes <= 1200,
            "Fixture did not exercise MTU-sized datagram loss and duplication");
    require(g.peers[0]->resources().inFlightStates <= WorldTransfer::maxInFlightStates,
            "Dropped receipts grew the UDP state cache");
    const Stage stage{1, 2, 0, 0, false, {}, {}};
    require(g.peers[0]->beginStage(stage), "Impaired floor event rejected");
    until([&] {
        g.poll();
        if (auto arrived = g.peers[1]->takeStage()) {
            require(*arrived == stage, "UDP floor recovery changed state");
            return true;
        }
        return false;
    });
    std::printf(
        "UDP received=%u last=%u largest_gap=%u actions=%u dropped=%u duplicates=%u mtu=%u\n",
        received, lastTick, largestGap, actions, g.relay->dropped.load(),
        g.relay->duplicated.load(), g.relay->maxBytes.load());
}
void udpLossRecovery() {
    udpLossRecoveryImpl(false);
}
void udpFragmentedRecovery() {
    // Opaque ~88 KiB changes exercise FEC, sequence-window crossings, paced
    // bursts and receipts while every seventh physical datagram is dropped.
    udpLossRecoveryImpl(true);
}
void loadingExit() {
    Group g(2);
    require(g.peers[0]->ready() && g.peers[0]->submit(0, {}), "Host setup failed");
    require(!g.peers[0]->take(), "Loading guest did not hold the initial frame");
    require(!g.peers[1]->command(Command::saveExit), "Guest could save the host run");
    require(g.peers[0]->command(Command::saveExit), "Host exit rejected while loading");
    const auto frame = g.peers[0]->take();
    require(frame && frame->tick == 0 && frame->commands[0] == Command::saveExit,
            "Initial readiness swallowed the host exit");
    require(!g.peers[0]->take(), "Host exit was consumed twice");
}
void loadingTimeout() {
    Group g(3);
    require(g.peers[0]->ready() && g.peers[0]->submit(0, {}), "Host setup failed");
    require(g.peers[1]->ready() && g.peers[1]->submit(0, {}), "Ready guest setup failed");
    const auto started = std::chrono::steady_clock::now();
    while (g.peers[0]->connectedMask() == 7) {
        // Keep the UDP peer responsive, but never acknowledge engine readiness.
        for (unsigned slot : {2u, 1u, 0u})
            g.peers[slot]->poll();
        require(g.peers[0]->phase() == Phase::running, "Loading timeout killed the host");
        require((g.peers[0]->connectedMask() & 3) == 3 && g.peers[1]->phase() == Phase::running,
                "Waiting for another loader disconnected an already ready guest");
        require(std::chrono::steady_clock::now() - started < std::chrono::seconds(65),
                "Unready peer was never removed");
        Sleep(10);
    }
    require(std::chrono::steady_clock::now() - started >= std::chrono::seconds(59),
            "Loading peer expired before its grace period");
    const auto frame = g.peers[0]->take();
    require(frame && frame->tick == 0 && frame->connected == 3,
            "Host did not resume after removing the unready peer");
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
void renderInputs() {
    Group g(3);
    g.ready();
    // Sequence zero is also the host's initial observation before any sample.
    require(g.peers[2]->submit(0, {}), "Initial slow guest sample rejected");
    for (unsigned tick = 0; tick < 60; ++tick) {
        InputFrame input;
        input.values[tick % 2] = 65535;
        input.triggered = tick % 3 == 0 ? 1u << 8 : 0;
        input.pointer = {true, 120.25f + tick, 456.5f};
        require(g.peers[1]->submit(tick * 2, input), "Render press rejected");
        require(g.peers[1]->submit(tick * 2 + 1, {}), "Render release rejected");
        require(g.peers[2]->submit(tick + 1, input), "30 Hz guest input rejected");
        until([&] {
            g.poll();
            return g.peers[0]->inputSequences()[1] == tick * 2 + 1 &&
                   g.peers[0]->inputSequences()[2] == tick + 1;
        });
        const auto frame = g.step(tick);
        require(frame.tick == tick, "Render input accelerated simulation");
        require(frame.inputs[1].values == InputFrame{}.values &&
                    frame.inputs[1].triggered == input.triggered && !frame.inputs[1].pointer.active,
                "Two render samples lost a release or replayed a button edge");
        require(frame.inputs[2] == input, "Mixed input rates changed the slower guest's input");
        require(!g.peers[0]->take(), "A render sample advanced simulation twice");
        g.publish(tick);
        for (unsigned slot = 1; slot < 3; ++slot) {
            std::optional<WorldState> state;
            until([&] {
                g.poll();
                state = g.peers[slot]->takeState();
                return state.has_value();
            });
            require(state->tick == tick && state->inputSequences[1] == tick * 2 + 1 &&
                        state->inputSequences[2] == tick + 1,
                    "Prediction confirmation confused mixed input rates with simulation ticks");
            g.peers[slot]->applied(tick);
        }
    }
    std::puts(
        "PASS mixed 30/60 Hz guest samples coalesce into 30 Hz host steps with one-shot edges and "
        "acknowledgements");
}
void inputBackpressure() {
    Group group(2);
    group.ready();
    group.step(0);
    InputFrame press;
    press.values[0] = 50000;
    press.triggered = 1u << 6;
    const InputRoom source{0, 84, 0};
    // Producer burst while the game does not poll. The background socket still
    // progresses; both handoff and socket queues must remain bounded.
    require(group.peers[1]->submit(0, press, source), "Press rejected");
    for (unsigned sequence = 1; sequence <= 10000; ++sequence)
        require(group.peers[1]->submit(sequence, {}, source), "Release sample rejected");
    require(group.peers[1]->resources().queuedBytes <= 16384,
            "Blocked input queue kept stale samples");
    until([&] {
        group.poll();
        return group.peers[0]->inputSequences()[1] == 10000;
    });
    const auto applied = group.step(1);
    require(applied.inputs[1].values == InputFrame{}.values && applied.inputs[1].triggered == 0,
            "Expired input event survived a 10000-sample backlog");
    require(group.peers[1]->submit(10001, press, source) &&
                group.peers[1]->submit(10002, {}, source),
            "Fresh press/release rejected");
    until([&] {
        group.poll();
        return group.peers[0]->inputSequences()[1] == 10002;
    });
    require(group.step(2).inputs[1].triggered == press.triggered,
            "Fresh reliable input event lost");
    require(group.step(3).inputs[1].triggered == 0, "Reliable input event repeated");

    Peer stalled;
    stalled.submitInput({0, press, source});
    for (unsigned sequence = 1; sequence <= 10000; ++sequence)
        stalled.submitInput({sequence, {}, source});
    require(stalled.outgoing.size() == 2 && stalled.queued < 256,
            "Unsent input retained obsolete directions");
    Peer peer;
    peer.submitInput({0, press, source});
    const auto first = peer.outgoing.front();
    peer.submitInput({1, {}, source});
    peer.submitInput({2, {}, source});
    require(peer.outgoing.size() == 2 && peer.outgoing.front() == first,
            "Coalescing changed a reliable button event");
    Writer pause(Message::control);
    pause.u8(static_cast<unsigned>(Command::pause));
    peer.sendMessage(pause);
    peer.submitInput({3, press, source});
    require(peer.outgoing.size() == 5, "Input replacement crossed an ordered control boundary");
    auto destination = source;
    destination.index = 85;
    peer.submitInput({4, {}, destination});
    Reader reader(peer.unsentTail(Message::input).subspan(1));
    const auto last = readInput(reader);
    reader.finish();
    require(last.sequence == 4 && last.room == destination && last.input.triggered == 0,
            "Old-room button edges crossed the destination boundary");
    std::size_t remaining = 0;
    for (const auto& message : peer.outgoing)
        remaining += message.size();
    require(peer.queued == remaining, "Replacement corrupted queued-byte accounting");
}
void floorRejoin() {
    Group g(2, 0, "127.0.0.1", {}, {1, 23});
    g.ready();
    g.step(0);
    InputFrame held;
    held.values[isaac::input::action::moveRight] = maxInputValue;
    held.pointer = {true, 321.5f, 278.25f};
    for (unsigned sequence = 0; sequence < 64; ++sequence)
        require(g.peers[1]->submit(sequence, held), "Previous connection input failed");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 63;
    });
    const auto identity = g.peers[1]->identity();
    g.peers[1]->close();
    until([&] {
        g.poll();
        return g.peers[0]->connectedMask() == 1;
    });
    require(g.step(1).connected == 1, "Departure did not remove guest from active roster");
    g.peers[1] = std::make_unique<TestSession>();
    require(g.peers[1]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, "other-mods",
                             testAccess()),
            "Returning connection failed");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::waiting;
    });
    require(g.peers[1]->settings().characters == g.peers[0]->settings().characters,
            "Fresh rejoin showed default characters while waiting for its checkpoint");
    require(g.peers[1]->choices()[0].character == 0 && g.peers[1]->choices()[1].character == 0,
            "Run roster overwrote independent lobby choices");
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
    require(g.peers[1]->settings().characters == checkpoint.characters,
            "Restoring the checkpoint changed the reconnect roster");
    require(g.peers[1]->ready(), "Restored engine ready failed");
    until([&] {
        g.poll();
        return g.peers[0]->connectedMask() == 3;
    });
    const auto rejoined = g.step(30);
    require(rejoined.connected == 3 && rejoined.inputs[1] == InputFrame{},
            "Ready guest was not restored with neutral input");
    g.publish(30);
    std::optional<WorldState> value;
    until([&] {
        g.poll();
        value = g.peers[1]->takeState();
        return value.has_value();
    });
    require(value->tick == 30, "Returning client replayed history instead of current state");
    require(value->inputSequences[1] == 0,
            "First rejoin view acknowledged input from the previous connection");
    g.peers[1]->applied(value->tick);
    require(g.peers[1]->submit(0, {}) && g.peers[1]->submit(1, held),
            "Rejoined input stream did not restart");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 1;
    });
    require(g.step(31).inputs[1] == held, "New connection input did not move its actor");
    g.publish(31);
    until([&] {
        g.poll();
        value = g.peers[1]->takeState();
        return value.has_value();
    });
    require(value->inputSequences[1] == 1, "Rejoin input acknowledgements did not advance");
    g.peers[1]->applied(value->tick);
    g.poll();
    std::puts("PASS rejoin loads current checkpoint then latest state; host continues during "
              "loading; no input-history replay");
}
void endingEvents() {
    // Exercise the catalog's actual terminal IDs: a rule must never encode
    // explicit completion as the protocol's game-over event.
    for (const auto& definition : isaac::compat::challenges::definitions) {
        const RunRules rules{definition.id, definition.version, definition.character,
                             definition.difficulty, definition.transient};
        Group group(4, definition.difficulty, "127.0.0.1", rules, {0, 1, 2, 3});
        group.ready();
        group.step(0);
        require(group.peers[0]->beginEnding(definition.ending, {}, true),
                "Catalog challenge completion was rejected");
        for (unsigned slot = 1; slot < group.count; ++slot) {
            std::optional<Ending> event;
            until([&] {
                group.poll();
                event = group.peers[slot]->takeEnding();
                return event.has_value();
            });
            require(event == Ending{definition.ending, {}, true},
                    "Catalog challenge completion did not reach a peer");
            if (definition.character == RunRules{}.character)
                require(group.peers[slot]->settings().characters[slot] == slot,
                        "Unrestricted challenge replaced a player's character");
        }
    }
    for (unsigned count = 2; count <= 4; ++count)
        for (unsigned scenario = 0; scenario < 5; ++scenario) {
            const RunRules rules = scenario == 1 || scenario == 2 || scenario == 4
                                       ? RunRules{1001, 2, 23, 0, true}
                                       : RunRules{};
            const bool completed = scenario == 2;
            const unsigned id = scenario >= 3 ? ending::gameOver : 6;
            Group group(count, 0, "127.0.0.1", rules);
            group.ready();
            group.step(0);
            if (!scenario)
                require(!group.peers[0]->beginEnding(6, {}, true),
                        "Ordinary run declared explicit rule completion");
            require(!group.peers[1]->beginEnding(id), "Replica published a terminal event");
            if (id == ending::gameOver)
                require(!group.peers[0]->beginEnding(id, {}, true),
                        "Game over was accepted as challenge completion");
            require(group.peers[0]->beginEnding(id, {}, completed), "Terminal event rejected");
            require(group.peers[0]->beginEnding(id, {}, completed), "Terminal replay rejected");
            require(!group.peers[0]->beginEnding(id, {}, !completed),
                    "Same ending ID changed native ending into explicit completion");
            for (unsigned slot = 1; slot < count; ++slot) {
                std::optional<Ending> event;
                until([&] {
                    group.poll();
                    event = group.peers[slot]->takeEnding();
                    return event.has_value();
                });
                require(event == Ending{id, {}, completed},
                        "Native ending and explicit completion were conflated on a replica");
                require(!group.peers[slot]->takeEnding(), "Terminal event was applied twice");
            }
        }
    for (const auto id : {8u, ending::gameOver}) {
        Group g(4);
        g.ready();
        g.step(0);
        g.publish(0, 40000);
        require(!g.peers[1]->beginEnding(id), "Client could choose the shared ending");
        for (auto invalid : {0u, 15u, 255u})
            require(!g.peers[0]->beginEnding(invalid), "Invalid ending was accepted");
        Progress progress;
        progress.achievements[7] = 1;
        progress.counters[21] = 5;
        require(g.peers[0]->beginEnding(id, progress), "Ending broadcast failed");
        require(g.peers[0]->beginEnding(id), "Duplicate native ending was not idempotent");
        require(!g.peers[0]->beginEnding(13), "A terminal event changed its ending");
        require(!g.peers[0]->beginStage({1, 2, 0, 0, false, {}, {}}),
                "A floor change followed the terminal event");
        WorldState obsolete;
        obsolete.tick = 0;
        obsolete.bytes = {1};
        require(!g.peers[0]->publish(1, obsolete), "World publication continued after the ending");
        // The engine closes immediately after its native exit callback. Every
        // replica must retain the ending even if finish and EOF arrive together.
        g.peers[0]->finish();
        until([&] {
            g.poll();
            return g.peers[1]->phase() == Phase::closed && g.peers[2]->phase() == Phase::closed &&
                   g.peers[3]->phase() == Phase::closed;
        });
        for (unsigned slot = 1; slot < 4; ++slot) {
            require(g.peers[slot]->takeEnding() == Ending{id, progress},
                    "Finish/EOF lost the native ending or its earned progress");
            require(!g.peers[slot]->takeEnding(), "A replica received the ending twice");
            require(!g.peers[slot]->takeState(), "Old world state survived the terminal event");
        }
    }
    std::puts(
        "PASS authoritative ending survives immediate finish/EOF and plays once on all peers");
}
void returnLobby() {
    for (unsigned count : {2u, 4u}) {
        Group g(count);
        g.ready();
        g.step(0);
        require(!g.peers[0]->returnToLobby() && !g.peers[1]->returnToLobby(),
                "Live game returned to selection");
        const auto port = g.peers[0]->port();
        std::array<std::string, maxPlayers> identities;
        for (unsigned slot = 0; slot < count; ++slot)
            identities[slot] = g.peers[slot]->identity();
        for (bool hostFirst : {true, false, true}) {
            // Every new run reuses its first floor epoch. Previous-run chunk
            // assembly and reference history must not survive that boundary.
            g.publish(0);
            for (unsigned slot = 1; slot < count; ++slot)
                until([&] {
                    g.poll();
                    if (auto world = g.peers[slot]->takeState()) {
                        g.peers[slot]->applied(world->tick);
                        return true;
                    }
                    return false;
                });
            Stage floor{1, 2, 0, 0, false, {}, {}};
            require(g.peers[0]->beginStage(floor), "Next run floor transition failed");
            g.step(1);
            g.publish(1);
            for (unsigned slot = 1; slot < count; ++slot)
                until([&] {
                    g.poll();
                    if (auto world = g.peers[slot]->takeState()) {
                        require(world->epoch == floor.epoch && world->tick == 1,
                                "Next run reused an old floor view");
                        g.peers[slot]->applied(world->tick);
                        return true;
                    }
                    return false;
                });
            const auto oldRun = g.peers[0]->runId();
            require(g.peers[0]->beginEnding(ending::firstCinematic), "Ending failed");
            for (unsigned slot = 1; slot < count; ++slot) {
                until([&] {
                    g.poll();
                    return g.peers[slot]->takeEnding().has_value();
                });
            }
            const auto first = hostFirst ? 0u : count - 1;
            require(g.peers[first]->returnToLobby() && g.peers[first]->returnToLobby(),
                    "Local return was not idempotent");
            for (unsigned attempt = 0; attempt < 30; ++attempt)
                g.poll();
            require(g.peers[first]->phase() == Phase::returning &&
                        g.peers[hostFirst ? count - 1 : 0]->phase() == Phase::running,
                    "First finisher interrupted a teammate's ending");
            auto settings = g.peers[0]->settings();
            require(!g.peers[0]->start(settings), "New game started over an unfinished ending");
            for (unsigned slot = 0; slot < count; ++slot)
                if (slot != first)
                    require(g.peers[slot]->returnToLobby(), "Remaining return failed");
            until([&] {
                g.poll();
                return std::all_of(g.peers.begin(), g.peers.begin() + count,
                                   [](const auto& peer) { return peer->phase() == Phase::lobby; });
            });
            for (unsigned slot = 0; slot < count; ++slot) {
                const auto& peer = g.peers[slot];
                require(peer->identity() == identities[slot] && peer->slot() == slot &&
                            peer->players() == count && !peer->takeEnding() && !peer->takeState() &&
                            !peer->takeRestart(),
                        "Lobby retained old gameplay or changed identities");
                require(!peer->choices()[slot].ready, "Lobby kept previous ready state");
                require(peer->choose({static_cast<std::uint16_t>(slot), false}),
                        "Lobby cannot change characters");
            }
            require(g.peers[0]->port() == port && !g.peers[0]->start(settings),
                    "Room replaced or unready roster started");
            for (unsigned slot = 0; slot < count; ++slot)
                require(g.peers[slot]->choose({static_cast<std::uint16_t>(slot), true}),
                        "New selection failed");
            until([&] {
                g.poll();
                for (unsigned slot = 0; slot < count; ++slot)
                    if (!g.peers[0]->choices()[slot].ready)
                        return false;
                return true;
            });
            settings.characters = {0, 1, 2, 3};
            settings.seed = hostFirst ? "QWERTY12" : "YV039KQF";
            require(g.peers[0]->start(settings), "Next lobby start failed");
            until([&] {
                g.poll();
                return std::all_of(g.peers.begin(), g.peers.begin() + count, [](const auto& peer) {
                    return peer->phase() == Phase::running;
                });
            });
            for (unsigned slot = 0; slot < count; ++slot)
                require(g.peers[slot]->runId() != oldRun &&
                            g.peers[slot]->runId() == g.peers[0]->runId() &&
                            g.peers[slot]->settings().characters == settings.characters,
                        "Next run reused old state or ignored new selection");
            g.ready();
            require(g.step(0).tick == 0, "Next run did not reset simulation");
        }
        require(g.peers[0]->beginEnding(ending::gameOver), "Game over failed");
        until([&] {
            g.poll();
            return g.peers[1]->takeEnding().has_value();
        });
        require(!g.peers[0]->returnToLobby() && !g.peers[1]->returnToLobby(),
                "Death result replaced restart voting with lobby return");
    }
    Group g(4);
    g.ready();
    g.step(0);
    require(g.peers[0]->beginEnding(ending::lastCinematic), "Ending failed");
    for (unsigned slot = 1; slot < 4; ++slot)
        until([&] {
            g.poll();
            return g.peers[slot]->takeEnding().has_value();
        });
    const auto identity = g.peers[3]->identity();
    for (unsigned slot : {0u, 2u, 3u})
        require(g.peers[slot]->returnToLobby(), "Return with disconnected peer failed");
    g.peers[1]->close();
    until([&] {
        g.poll();
        return g.peers[3]->phase() == Phase::lobby;
    });
    require(g.peers[0]->players() == 3 && g.peers[3]->slot() == 2 &&
                g.peers[3]->identity() == identity && g.peers[0]->connectedMask() == 7,
            "Departed seat blocked or corrupted the new lobby");
    std::puts("PASS completed runs return to selection together, retaining room and identities");
}
void restartRuns() {
    for (unsigned count : {2u, 4u}) {
        Group g(count, 1, "127.0.0.1", {}, {0, 1, 2, 3});
        g.ready();
        g.step(0);
        const auto identities = [&] {
            std::array<std::string, maxPlayers> values;
            for (unsigned slot = 0; slot < count; ++slot)
                values[slot] = g.peers[slot]->identity();
            return values;
        }();
        for (bool ended : {false, true, false}) {
            g.publish(0, 12000);
            g.poll();
            // Leave previous-run input and receipt traffic in flight.
            for (unsigned slot = 1; slot < count; ++slot) {
                if (auto world = g.peers[slot]->takeState())
                    g.peers[slot]->applied(world->tick);
                require(g.peers[slot]->submit(0, {}), "Old input not queued");
            }
            if (ended)
                require(g.peers[0]->beginEnding(ending::gameOver), "Game over failed");
            const auto oldRun = g.peers[0]->runId();
            const auto oldEpoch = g.peers[0]->worldEpoch();
            auto settings = g.peers[0]->settings();
            settings.seed = settings.seed == "YV039KQF" ? "QWERTY12" : "YV039KQF";
            require(!g.peers[1]->restart(settings), "Guest initiated authoritative reset");
            require(g.peers[0]->restart(settings), "Host restart failed");
            require(!g.peers[0]->restart(settings), "Repeated restart accepted before readiness");
            until([&] {
                g.poll();
                for (unsigned slot = 1; slot < count; ++slot)
                    if (g.peers[slot]->runId() == oldRun)
                        return false;
                return true;
            });
            for (unsigned slot = 0; slot < count; ++slot) {
                auto& peer = *g.peers[slot];
                require(peer.takeRestart() && !peer.takeRestart(), "Reset was not one-shot");
                require(peer.identity() == identities[slot] && peer.slot() == slot &&
                            peer.players() == count && peer.connectedMask() == (1u << count) - 1,
                        "Restart changed the room membership");
                require(peer.settings().seed == settings.seed && peer.settings().difficulty == 1 &&
                            peer.settings().characters == settings.characters &&
                            peer.worldEpoch() > oldEpoch && !peer.takeEnding() && !peer.takeState(),
                        "New run retained old state or lost settings");
            }
            require(!g.peers[0]->take(), "New run simulated before readiness");
            require(!g.peers[0]->sendLifecycle(1, "initial vote state") &&
                        !g.peers[1]->sendLifecycle(0, "consent"),
                    "Lifecycle delivery reported success before local readiness");
            require(g.peers[0]->ready(), "Host could not load the fresh run");
            require(!g.peers[0]->sendLifecycle(1, "initial vote state"),
                    "Initial vote state would be lost while guest loads");
            g.ready();
            require(g.step(0).tick == 0, "New run did not reset simulation ticks");
            require(g.peers[1]->sendLifecycle(0, "consent"), "Lifecycle channel failed");
            std::optional<IntegrationMessage> vote;
            until([&] {
                g.poll();
                vote = g.peers[0]->takeLifecycle();
                return vote.has_value();
            });
            require(vote->sender == 1 && vote->bytes == "consent", "Vote sender was not preserved");
        }
    }
    {
        Group g(3);
        g.ready();
        g.step(0);
        const auto identity = g.peers[1]->identity();
        g.peers[1]->close();
        g.peers[1].reset();
        until([&] {
            g.poll();
            return g.peers[0]->connectedMask() == 5;
        });
        auto settings = g.peers[0]->settings();
        settings.seed = "QWERTY12";
        require(g.peers[0]->restart(settings), "A disconnected seat prevented restart");
        until([&] {
            g.poll();
            return g.peers[2]->runId() == g.peers[0]->runId();
        });
        require(g.peers[2]->slot() == 2 && g.peers[2]->connectedMask() == 5,
                "Restart compacted or revived an absent seat");
        require(g.peers[0]->ready() && g.peers[2]->ready(), "Survivors could not load new run");
        g.step(0);
        g.peers[1] = std::make_unique<TestSession>();
        require(g.peers[1]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, {},
                                 testAccess()),
                "Returning seat could not reconnect after restart");
        until([&] {
            g.poll();
            return g.peers[1]->phase() == Phase::waiting;
        });
        require(g.peers[1]->slot() == 1, "Restart lost a returning player's identity");
        require(!g.peers[0]->restart(settings), "Restart interrupted checkpoint admission");
    }
    std::puts(
        "PASS repeated new-run barriers preserve seats, reject stale state, and clear endings");
}
void endingLiveness() {
    Group g(4);
    g.ready();
    g.step(0);
    g.publish(0);
    for (unsigned slot = 1; slot < g.count; ++slot)
        until([&] {
            g.poll();
            if (const auto state = g.peers[slot]->takeState()) {
                g.peers[slot]->applied(state->tick);
                return true;
            }
            return false;
        });
    require(g.peers[0]->beginEnding(ending::gameOver), "Game-over event rejected");
    // Outlive both gameplay watchdogs (15 s inputs, 20 s snapshots). Terminal
    // screens exchange only transport heartbeats until the user dismisses them.
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(22);
    while (std::chrono::steady_clock::now() < deadline) {
        g.poll();
        require(g.peers[0]->connectedMask() == 15, "Game-over screen lost a healthy peer");
        Sleep(5);
    }
    for (unsigned slot = 1; slot < g.count; ++slot) {
        require(g.peers[slot]->takeEnding() == Ending{ending::gameOver, {}},
                "Waiting on game over lost its event");
        require(g.peers[slot]->phase() == Phase::running,
                "Terminal heartbeat did not preserve the connection");
    }
}
void cinematicEvents() {
    Group g(4);
    g.ready();
    const auto frame = g.step(0);
    g.publish(frame.tick, 300000);
    Stage movie;
    movie.epoch = 1;
    movie.level = 13;
    movie.type = 1;
    movie.animation = 1;
    movie.cinematic = 25;
    require(!g.peers[1]->beginStage(movie), "Client initiated the shared cinematic");
    for (const auto field : {0, 1, 2, 3, 4, 5}) {
        auto invalid = movie;
        switch (field) {
        case 0:
            invalid.cinematic = 24;
            break;
        case 1:
            invalid.level = 12;
            break;
        case 2:
            invalid.type = 0;
            break;
        case 3:
            invalid.animation = 2;
            break;
        case 4:
            invalid.same = true;
            break;
        case 5:
            invalid.rewind = {1};
            break;
        }
        require(!g.peers[0]->beginStage(invalid), "Invalid native cinematic accepted");
    }
    require(g.peers[0]->beginStage(movie), "Native cinematic broadcast failed");
    for (unsigned slot = 1; slot < g.count; ++slot) {
        std::optional<Stage> received;
        until([&] {
            g.poll();
            received = g.peers[slot]->takeStage();
            return received.has_value();
        });
        require(*received == movie && g.peers[slot]->cinematicActive(),
                "Replica lost the native cinematic or its barrier");
        require(!g.peers[slot]->takeState(), "Old world crossed the cinematic boundary");
    }
    require(!g.peers[0]->beginStage(movie), "Overlapping cinematic accepted");
    require(!g.peers[0]->take(), "Simulation advanced during a shared cinematic");
    WorldState obsolete;
    obsolete.tick = frame.tick;
    obsolete.bytes = {1};
    require(!g.peers[0]->publish(1, obsolete), "World advanced during a shared cinematic");
    // Native videos stop input and world frames. Reliable heartbeats must keep
    // the connection alive beyond both normal simulation timeout deadlines.
    const auto wait = std::chrono::steady_clock::now() + std::chrono::seconds(21);
    while (std::chrono::steady_clock::now() < wait) {
        g.poll();
        Sleep(10);
    }
    require(g.peers[0]->cinematicReady(), "Host could not finish its native movie");
    require(g.peers[1]->cinematicReady() && g.peers[1]->cinematicReady(),
            "Local cinematic readiness was not idempotent");
    require(g.peers[2]->cinematicReady(), "Third player readiness failed");
    g.poll();
    require(g.peers[0]->cinematicActive(), "Faster peers skipped the slow player's movie");
    require(g.peers[3]->cinematicReady(), "Last player readiness failed");
    until([&] {
        g.poll();
        return std::all_of(g.peers.begin(), g.peers.end(),
                           [](const auto& p) { return !p->cinematicActive(); });
    });
    require(!g.peers[0]->cinematicReady(), "Readiness accepted outside a cinematic");
    const auto resumed = g.step(1);
    g.publish(resumed.tick);
    until([&] {
        g.poll();
        return g.peers[1]->takeState().has_value();
    });
    std::puts(
        "PASS native shared cinematic preserves heartbeat, ordering and all-player readiness");
}
void stageEvents() {
    Group g(2, 0, "127.0.0.1", {}, {1, 23});
    g.ready();
    g.step(0);
    g.publish(0, 40000);
    // Supersede a view that may be only partly queued, then publish the new
    // floor. The event must survive state coalescing and preserve native args.
    Stage stage{1, 1, 0, 0, false, {}, {}};
    for (unsigned i = 0; i < stage.seeds.size(); ++i)
        stage.seeds[i] = 0x12340000 + i;
    stage.stateFlags = {0x10000, (1u << (44 - 32)) | (1u << (48 - 32))};
    stage.sourceRoom = -8;
    for (int invalidRoom : {-21, 169}) {
        auto invalid = stage;
        invalid.sourceRoom = invalidRoom;
        require(!g.peers[0]->beginStage(invalid), "Invalid floor source room accepted");
    }
    require(g.peers[0]->beginStage(stage), "Stage broadcast failed");
    std::optional<Stage> received;
    until([&] {
        g.poll();
        received = g.peers[1]->takeStage();
        return received.has_value();
    });
    require(received->stateFlags == stage.stateFlags,
            "Native floor event lost alternate-route and ascent flags");
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
    auto checkpoint = g.peers[0]->settings();
    checkpoint.characters = {7, 2};
    checkpoint.snapshot = {1};
    require(g.peers[0]->checkpoint(checkpoint, 2), "Updated roster checkpoint failed");
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
    require(g.peers[1]->settings().characters == checkpoint.characters,
            "Automatic return lost the current roster or reused the original characters");
    require(g.peers[0]->beginStage({2, 2, 0, 0, false, {}, {}}), "Second stage broadcast failed");
    g.poll();
    require(!g.peers[1]->takeStage() && g.peers[1]->phase() == Phase::waiting,
            "Waiting player entered an online floor animation");
    g.peers[1]->close();
    until([&] {
        g.peers[0]->poll();
        return g.peers[0]->connectedMask() == 1;
    });
    require(g.peers[1]->reconnect(), "Manual return after closing failed");
    require(!g.peers[1]->reconnect(), "Repeated click replaced an in-flight connection");
    require(!g.peers[0]->reconnect(), "Host reconnected to itself");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::waiting;
    });
    require(g.peers[1]->identity() == identity && g.peers[1]->slot() == 1,
            "Manual return lost player identity or seat");
    std::puts("PASS native floor begin precedes new state; automatic return retains identity until "
              "a checkpoint is supplied");
}
void stageDuringRejoin() {
    Group g(2);
    g.ready();
    g.step(0);
    const auto identity = g.peers[1]->identity();
    g.peers[1]->close();
    until([&] {
        g.poll();
        return g.peers[0]->connectedMask() == 1;
    });
    g.step(1);
    g.peers[1] = std::make_unique<TestSession>();
    require(
        g.peers[1]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, {}, testAccess()),
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
    Stage last{2, 2, 0, 0, false, {}, {}};
    last.stateFlags[1] = 1u << (44 - 32);
    last.sourceRoom = -8;
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
    value.stateFlags[1] = 1u << (44 - 32);
    value.sourceRoom = -9;
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
    for (unsigned restart : {1u, 2u}) {
        Group g(2);
        g.ready();
        g.step(0);
        Stage value;
        value.epoch = 1;
        value.level = 1;
        value.restart = restart;
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
        auto invalid = value;
        invalid.restart = 3;
        require(!g.peers[0]->beginStage(invalid), "Unbounded native restart kind was accepted");
        invalid = value;
        invalid.same = true;
        require(!g.peers[0]->beginStage(invalid), "Native restart mixed with same-floor animation");
    }
    std::puts("PASS native restart kinds preserve pre-restart seeds and precede world state");
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
    press.triggered |= menuActionMask;
    require(g.peers[1]->submit(4, press, source), "Source menu press failed");
    auto intro = destination;
    intro.introSerial = 19;
    intro.introActive = true;
    require(g.peers[1]->submit(5, {}, intro), "Intro room input failed");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 5;
    });
    frame = g.step(3);
    require(frame.inputRooms[1] == intro && frame.inputs[1].triggered == menuActionMask,
            "Room transfer swallowed a menu edge or lost intro acknowledgement");
    require(g.peers[1]->submit(6, press, intro), "Intro gameplay input failed");
    intro.introActive = false;
    require(g.peers[1]->submit(7, {}, intro), "Intro completion input failed");
    until([&] {
        g.poll();
        return g.peers[0]->inputSequences()[1] == 7;
    });
    frame = g.step(4);
    require(frame.inputRooms[1] == intro && frame.inputs[1].triggered == press.triggered,
            "Intro completion discarded input from the same room");
    std::puts("PASS input room identity and edges stay within room boundaries");
}
void compressionLimits() {
    StateCompression compression;
    rejects([&] { compression.compress({}); }, "Empty state accepted");
    rejects([&] { compression.compress(std::vector<std::uint8_t>(maxWorldSize + 1)); },
            "Oversized state accepted");
    for (const auto& plain :
         {std::vector<std::uint8_t>{0xff}, std::vector<std::uint8_t>(maxWorldSize, 42)}) {
        require(compression.expand(compression.compress(plain)) == plain,
                "Compression boundary round trip failed");
        require(compression.expand(compression.compress(plain, plain), plain) == plain,
                "Prefix compression raw fallback or maximum size failed");
    }
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
    invalid[0] = 255;
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
    TestSession host, guest;
    require(!host.ready() && !host.submit(0, {}) && !host.command(Command::pause),
            "Idle session accepted gameplay");
    require(host.host(0, "test", "mods", testAccess()), "Host failed");
    Start start;
    start.seed = "YV039KQF";
    require(!host.start(start), "Single-player lobby started");
    require(guest.join("127.0.0.1", host.port(), "test", {}, "mods", testAccess()), "Join failed");
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
void runRules() {
    const RunRules rules{1001, 2, 23, 0, true, 1};
    TestSession host, guest;
    require(host.host(0, "test", {}, testAccess()), "Host failed");
    require(guest.join("127.0.0.1", host.port(), "test", {}, {}, testAccess()), "Join failed");
    auto poll = [&] {
        host.poll();
        guest.poll();
    };
    until([&] {
        poll();
        return host.players() == 2 && guest.phase() == Phase::lobby;
    });
    require(!guest.configureRules(rules), "Guest changed run rules");
    require(host.configureRules(rules), "Host configuration failed");
    until([&] {
        poll();
        return guest.rules() == rules;
    });
    require(host.choices()[0].character == 23 && guest.choices()[1].character == 23,
            "Lobby did not publish locked characters");
    require(!guest.choose({0, true}) && !host.choose({0, true}), "Character lock bypassed");
    require(guest.choose({23, true}) && host.choose({23, true}), "Ready failed");
    guest.poll(); // Old ready packet is now on the wire, before the host changes rules.
    auto revised = rules;
    revised.version = 3;
    require(host.configureRules(revised), "Revision failed");
    until([&] {
        poll();
        return guest.rules() == revised;
    });
    for (int i = 0; i < 10; ++i)
        poll();
    require(!host.choices()[0].ready && !host.choices()[1].ready,
            "Old ready packet accepted after rules changed");
    Start value;
    value.seed = "YV039KQF";
    value.rules = revised;
    value.characters.fill(23);
    require(!host.start(value), "Unready rule revision started");
    require(host.choose({23, true}) && guest.choose({23, true}), "Revised ready failed");
    until([&] {
        poll();
        return host.choices()[1].ready;
    });
    value.difficulty = 1;
    require(!host.start(value), "Locked difficulty bypassed");
    value.difficulty = 0;
    value.rules = rules;
    require(!host.start(value), "Stale start rules accepted");
    require(host.configureRules({}), "Cannot leave challenge mode");
    until([&] {
        poll();
        return guest.rules().id == 0;
    });
    require(guest.choose({7, false}), "Normal character selection was not restored");
    for (unsigned n = 2; n <= 4; ++n) {
        Group g(n, 0, "127.0.0.1", rules);
        g.ready();
        g.step(0);
        const unsigned slot = n - 1;
        const auto identity = g.peers[slot]->identity();
        g.peers[slot]->close();
        const auto mask = ((1u << n) - 1) & ~(1u << slot);
        until([&] {
            g.poll();
            return g.peers[0]->connectedMask() == mask;
        });
        require(g.step(1).connected == mask, "Disconnected seat remained active");
        g.peers[slot] = std::make_unique<TestSession>();
        require(g.peers[slot]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, {},
                                    testAccess()),
                "Challenge rejoin failed");
        until([&] {
            g.poll();
            return g.peers[slot]->phase() == Phase::waiting;
        });
        auto checkpoint = g.peers[0]->settings();
        checkpoint.snapshot.resize(6507, 42);
        auto wrong = checkpoint;
        wrong.rules = {};
        require(!g.peers[0]->checkpoint(wrong, 2), "Rejoin changed live run rules");
        require(g.peers[0]->checkpoint(checkpoint, 2), "Challenge checkpoint rejected");
        until([&] {
            g.poll();
            return g.peers[slot]->phase() == Phase::running;
        });
        require(g.peers[slot]->rules() == rules && g.peers[slot]->settings().rules == rules &&
                    g.peers[slot]->slot() == slot &&
                    g.peers[slot]->settings().snapshot == checkpoint.snapshot,
                "Rejoin lost challenge identity, roster or snapshot");
        require(g.peers[slot]->ready(), "Rejoined engine rejected");
        until([&] {
            g.poll();
            return g.peers[0]->connectedMask() == (1u << n) - 1;
        });
    }
}
struct WirePeer {
    ENetHost* endpoint = nullptr;
    ENetPeer* peer = nullptr;
    explicit WirePeer(bool listen = false) {
        require(enet_initialize() == 0, "Wire fixture initialization failed");
        ENetAddress address{ENET_HOST_ANY, 0};
        endpoint = enet_host_create(listen ? &address : nullptr, 1, datagram::channelCount, 0, 0);
        require(endpoint != nullptr, "Wire fixture endpoint failed");
        endpoint->checksum = enet_crc32;
        endpoint->mtu = datagram::mtu - sizeof(enet_uint32);
    }
    ~WirePeer() {
        enet_host_destroy(endpoint);
        enet_deinitialize();
    }
    void connect(std::uint16_t port) {
        const ENetAddress address{htonl(INADDR_LOOPBACK), port};
        peer = enet_host_connect(endpoint, &address, datagram::channelCount, protocolVersion);
        require(peer != nullptr, "Wire fixture connect failed");
    }
    void poll() {
        ENetEvent event{};
        while (enet_host_service(endpoint, &event, 0) > 0) {
            if (event.type == ENET_EVENT_TYPE_CONNECT)
                peer = event.peer;
            else if (event.type == ENET_EVENT_TYPE_RECEIVE)
                enet_packet_destroy(event.packet);
        }
    }
    void send(const Writer& message) {
        Writer envelope(static_cast<Message>(datagram::Envelope::message));
        envelope.u32(0);
        envelope.bytes.insert(envelope.bytes.end(), message.bytes.begin(), message.bytes.end());
        auto* packet = enet_packet_create(envelope.bytes.data(), envelope.bytes.size(),
                                          ENET_PACKET_FLAG_RELIABLE);
        require(packet && enet_peer_send(peer, datagram::reliableChannel, packet) == 0,
                "Wire fixture send failed");
        enet_host_flush(endpoint);
    }
};
void roomOptions() {
    TestSession host, guest;
    require(host.host(0, "test", {}, testAccess()), "Host failed");
    require(guest.join("127.0.0.1", host.port(), "test", {}, {}, testAccess()), "Join failed");
    auto poll = [&] {
        host.poll();
        guest.poll();
    };
    until([&] {
        poll();
        return host.players() == 2 && guest.phase() == Phase::lobby;
    });
    require(host.publishChoicePreview(0, 0x1000001) && guest.publishChoicePreview(0, 0x1000002),
            "Initial personal preview failed");
    until([&] {
        poll();
        return guest.choices()[0].preview == 0x1000001 && host.choices()[1].preview == 0x1000002;
    });
    require(host.choose({0, true, 0x1000001}) && guest.choose({0, true, 0x1000002}),
            "Ready failed");
    until([&] {
        poll();
        return host.choices()[1].ready;
    });
    require(guest.publishChoicePreview(0, 0x1000022), "Preview refresh failed");
    until([&] {
        poll();
        return host.choices()[1].preview == 0x1000022;
    });
    require(host.choices()[1].ready && host.choices()[0].preview == 0x1000001,
            "Preview changed readiness or another peer's card");
    RunRules enabled;
    enabled.options = 1;
    require(!guest.configureRules(enabled) && host.configureRules(enabled),
            "Room option authority incorrect");
    until([&] {
        poll();
        return guest.rules() == enabled;
    });
    require(!host.choices()[0].ready && !host.choices()[1].ready &&
                guest.choices()[0].preview == 0x1000001,
            "Option change lost marks or retained readiness");
    require(guest.choose({1, false, 0x1000010}), "Character selection failed");
    // An old-character refresh can already be in flight when a new choice arrives.
    require(guest.publishChoicePreview(0, 0x1000002), "Old local character was not published");
    until([&] {
        poll();
        return guest.choices()[1].character == 1;
    });
    require(host.choices()[1].preview == 0x1000010, "Stale preview replaced the new character");
    require(host.choose({0, true, 0x1000001}) && guest.choose({1, true, 0x1000010}),
            "New rule readiness failed");
    until([&] {
        poll();
        return host.choices()[1].ready;
    });
    Start start;
    start.seed = "YV039KQF";
    start.characters[1] = 1;
    require(!host.start(start), "Stale room options started");
    start.rules = enabled;
    // Cosmetic metadata arriving after Start must be harmless.
    require(guest.publishChoicePreview(1, 0x1000020), "Late preview enqueue failed");
    require(host.start(start), "Configured normal run did not start");
    until([&] {
        poll();
        return guest.phase() == Phase::running;
    });
    require(host.phase() == Phase::running && guest.settings().rules == enabled,
            "Late metadata interrupted start or dropped room options");
}

void wireRules(Writer& writer, const RunRules& rules) {
    writer.u16(rules.id);
    writer.u16(rules.version);
    writer.u16(rules.character);
    writer.u8(rules.difficulty);
    writer.u8(rules.transient);
    writer.u32(rules.options);
}
void accessWireValidation() {
    const LobbyAccess basic{{0}, {}, {0}};
    // Bypass Session::choose to exercise the authority's untrusted wire boundary.
    {
        TestSession host;
        require(host.host(0, "wire-access", {}, testAccess()), "Wire host failed");
        WirePeer remote;
        remote.connect(host.port());
        until([&] {
            host.poll();
            remote.poll();
            return remote.peer->state == ENET_PEER_STATE_CONNECTED;
        });
        Writer hello(Message::hello);
        hello.u16(protocolVersion);
        hello.string("wire-access");
        hello.string(std::string(32, 'a'));
        hello.string("");
        hello.access(basic);
        remote.send(hello);
        until([&] {
            host.poll();
            remote.poll();
            return host.players() == 2;
        });
        const auto choose = [&](std::uint16_t character) {
            Writer choice(Message::choice);
            choice.u32(0);
            choice.u16(character);
            choice.u8(1);
            choice.u32(0);
            remote.send(choice);
            Writer marker(Message::integration);
            const std::array<std::uint8_t, 1> bytes{1};
            marker.blob(bytes);
            remote.send(marker);
            until([&] {
                host.poll();
                remote.poll();
                return host.takeIntegration().has_value();
            });
        };
        choose(23);
        require(host.choices()[1] == Choice{}, "Raw choice bypassed local character access");
        choose(0);
        require(host.choices()[1] == Choice{0, true}, "Raw allowed choice rejected");
    }
    // A host cannot replace this peer's declaration or force an inaccessible start.
    for (unsigned scenario = 0; scenario < 5; ++scenario) {
        TestSession guest;
        WirePeer remote(true);
        require(
            guest.join("127.0.0.1", remote.endpoint->address.port, "wire-access", {}, {}, basic),
            "Wire guest failed");
        until([&] {
            guest.poll();
            remote.poll();
            return remote.peer != nullptr;
        });
        Writer welcome(Message::welcome);
        welcome.u8(1);
        remote.send(welcome);
        const RunRules rules = scenario == 1 ? RunRules{1001, 2, 23, 0, true} : RunRules{};
        Writer lobby(Message::lobby);
        lobby.u8(2);
        lobby.u8(1);
        lobby.u32(0);
        wireRules(lobby, rules);
        for (unsigned i = 0; i < maxPlayers; ++i) {
            lobby.u16(0);
            lobby.u8(0);
            lobby.u32(0);
        }
        lobby.access(testAccess());
        lobby.access(scenario == 2 ? testAccess() : basic);
        lobby.access({});
        lobby.access({});
        remote.send(lobby);
        if (scenario != 2) {
            Writer start(Message::start);
            wireRules(start, rules);
            start.string("YV039KQF");
            start.u8(0);
            for (unsigned i = 0; i < maxPlayers; ++i)
                start.u16(i == 1 && scenario < 3 ? 23 : 0);
            start.progress(std::nullopt);
            start.string(std::string(32, 'b'));
            start.u32(0);
            start.u32(0);
            start.u8(3);
            start.u32(0);
            start.u64(snapshotHash({}));
            remote.send(start);
            if (scenario >= 3) {
                Writer ending(Message::ending);
                ending.u8(6);
                ending.u8(scenario == 3 ? 1 : 2);
                ending.progress(Progress{});
                remote.send(ending);
            }
        }
        until([&] {
            guest.poll();
            remote.poll();
            return guest.phase() == Phase::failed;
        });
        require(guest.error().find(scenario >= 3   ? "Invalid authoritative ending"
                                   : scenario == 2 ? "changed local"
                                                   : "unavailable") != std::string::npos,
                "Client rejected forged access for an unrelated reason");
    }
}
void lobbyAccess() {
    accessWireValidation();
    const RunRules rules{1001, 2, 23, 0, true};
    const LobbyAccess basic{{0}, {}, {0}};
    require(LobbyAccess{}.valid() && !LobbyAccess{}.allowsCharacter(0) &&
                !LobbyAccess{}.allowsRules(rules),
            "Empty profile declaration granted access");
    LobbyAccess maximum;
    for (unsigned i = 0; i < 256; ++i)
        maximum.characters.push_back(i);
    maximum.unlockedCharacters = maximum.characters;
    for (unsigned i = 1; i <= 64; ++i)
        maximum.rules.push_back({static_cast<std::uint16_t>(i), 1});
    Writer encoded(Message::lobby);
    for (unsigned i = 0; i < maxPlayers; ++i)
        encoded.access(maximum);
    require(encoded.bytes.size() + 64 <= maxMessageSize, "Access roster exceeds message bound");
    Reader roundtrip(encoded.bytes);
    roundtrip.u8();
    for (unsigned i = 0; i < maxPlayers; ++i)
        require(roundtrip.access() == maximum, "Access round trip changed IDs");
    roundtrip.finish();
    Writer single(Message::hello);
    single.access(testAccess());
    for (std::size_t length = 1; length < single.bytes.size(); ++length)
        rejects(
            [&] {
                Reader shortRead(std::span(single.bytes).first(length));
                shortRead.u8();
                shortRead.access();
            },
            "Truncated access declaration accepted");
    const std::vector<LobbyAccess> invalidAccess{
        {{0, 0}, {}, {0}},
        {{1, 0}, {}, {0, 1}},
        {{65535}, {}, {65535}},
        {{0}, {{0, 1}}, {0}},
        {{0}, {{1, 0}}, {0}},
        {{0}, {{2, 1}, {1, 1}}, {0}},
        {{0}, {{1, 1}, {1, 1}}, {0}},
        {{0}, {}, {}},
        {{0}, {}, {0, 0}},
    };
    for (const auto& invalid : invalidAccess) {
        require(!invalid.valid(), "Invalid access IDs accepted");
        rejects([&] { single.access(invalid); }, "Invalid access encoded");
        TestSession rejected;
        require(!rejected.host(0, "access-test", {}, invalid), "Host accepted invalid access");
    }
    maximum.characters.push_back(256);
    require(!maximum.valid(), "Oversized character list accepted");
    maximum.characters.pop_back();
    maximum.rules.push_back({65, 1});
    require(!maximum.valid(), "Oversized rule list accepted");
    for (const auto& bytes : std::vector<std::vector<std::uint8_t>>{{1, 1},
                                                                    {0, 0, 65},
                                                                    {0, 2, 0, 0, 0, 0, 0, 0},
                                                                    {0, 0, 1, 0, 0, 0, 1},
                                                                    {0, 1, 0, 0, 2, 0}})
        rejects(
            [&] {
                Reader invalid(bytes);
                invalid.access();
            },
            "Malformed access wire data accepted");

    struct Lobby {
        std::vector<std::unique_ptr<TestSession>> peers;
        explicit Lobby(const std::vector<LobbyAccess>& profiles) {
            peers.push_back(std::make_unique<TestSession>());
            require(peers[0]->host(0, "access-test", {}, profiles[0]), "Access host failed");
            for (std::size_t i = 1; i < profiles.size(); ++i)
                add(profiles[i]);
        }
        void poll() {
            for (auto& peer : peers)
                if (peer) {
                    peer->poll();
                    require(peer->phase() != Phase::failed, peer->error().c_str());
                }
        }
        void add(const LobbyAccess& profile) {
            peers.push_back(std::make_unique<TestSession>());
            require(
                peers.back()->join("127.0.0.1", peers[0]->port(), "access-test", {}, {}, profile),
                "Access guest failed");
            until([&] {
                poll();
                return std::all_of(peers.begin(), peers.end(), [&](const auto& peer) {
                    return peer->players() == peers.size();
                });
            });
        }
        void chooseAll(std::uint16_t character) {
            for (auto& peer : peers)
                require(peer->choose({character, true}), "Allowed choice rejected");
            until([&] {
                poll();
                for (unsigned i = 0; i < peers.size(); ++i)
                    if (!peers[0]->choices()[i].ready)
                        return false;
                return true;
            });
        }
    };
    // No participant may borrow the host's access, including saved-seat Resume.
    for (unsigned n = 2; n <= 4; ++n) {
        for (unsigned locked = 0; locked < n; ++locked) {
            std::vector<LobbyAccess> profiles(n, testAccess());
            profiles[locked] = basic;
            Lobby lobby(profiles);
            for (unsigned i = 0; i < n; ++i) {
                require(lobby.peers[i]->localAccess() == profiles[i], "Local access changed");
                require(!lobby.peers[i]->rulesAvailable(rules), "Shared unlock leaked to a peer");
                for (unsigned j = 0; j < n; ++j)
                    require(lobby.peers[i]->access()[j] == profiles[j], "Roster access mismatch");
            }
            require(!lobby.peers[0]->configureRules(rules), "Locked participant entered rules");
            require(!lobby.peers[locked]->choose({23, false}) &&
                        !lobby.peers[locked]->choose({23, true}),
                    "Locked local character could be selected or readied");
            lobby.chooseAll(0);
            Start start;
            start.seed = "YV039KQF";
            start.characters[locked] = 23;
            require(!lobby.peers[0]->start(start), "Host started a locked character");
            start.snapshot.resize(123, 42);
            require(!lobby.peers[0]->start(start), "Resume bypassed saved character access");
            start.characters[locked] = 0;
            require(lobby.peers[0]->start(start), "Allowed ordinary Resume rejected");
            until([&] {
                lobby.poll();
                return std::all_of(lobby.peers.begin(), lobby.peers.end(), [](const auto& peer) {
                    return peer->phase() == Phase::running;
                });
            });
        }
        // A permitted forced character is insufficient without its rule key.
        auto missingRule = testAccess();
        missingRule.rules.clear();
        std::vector<LobbyAccess> profiles(n, testAccess());
        profiles.back() = missingRule;
        Lobby noRule(profiles);
        require(!noRule.peers[0]->configureRules(rules), "Missing rule key ignored");
    }
    // Empty declarations are fail-closed even through a direct start call.
    {
        Lobby empty({{}, {}});
        Start start;
        start.seed = "YV039KQF";
        require(!empty.peers[0]->choose({0, true}) && !empty.peers[0]->start(start),
                "Missing profile declaration granted an implicit default character");
    }
    // A consumed new-run resource must not lock an already unlocked saved actor.
    {
        const LobbyAccess noResource{{0}, {}, {0, 9}};
        Lobby lobby({basic, noResource});
        lobby.chooseAll(0);
        Start start;
        start.seed = "YV039KQF";
        start.characters[1] = 9;
        require(!lobby.peers[1]->choose({9, true}) && !lobby.peers[0]->start(start),
                "Unavailable new-run character was selected");
        start.snapshot.resize(123, 42);
        require(lobby.peers[0]->start(start), "Resume consumed new-run availability again");
        until([&] {
            lobby.poll();
            return lobby.peers[1]->phase() == Phase::running;
        });
        require(lobby.peers[0]->ready() && lobby.peers[1]->ready(), "Resume ready failed");
        until([&] {
            lobby.poll();
            return lobby.peers[0]->connectedMask() == 3;
        });
        const auto identity = lobby.peers[1]->identity();
        lobby.peers[1]->close();
        lobby.peers[1].reset();
        until([&] {
            lobby.poll();
            return lobby.peers[0]->connectedMask() == 1;
        });
        lobby.peers[1] = std::make_unique<TestSession>();
        require(lobby.peers[1]->join("127.0.0.1", lobby.peers[0]->port(), "access-test", identity,
                                     {}, noResource),
                "Unlocked rejoin failed");
        until([&] {
            lobby.poll();
            return lobby.peers[1]->phase() == Phase::waiting;
        });
        require(lobby.peers[0]->checkpoint(start, 0), "Unlocked rejoin checkpoint failed");
        until([&] {
            lobby.poll();
            return lobby.peers[1]->phase() == Phase::running;
        });
        require(lobby.peers[1]->settings().characters[1] == 9,
                "Rejoin replaced an unlocked saved actor");
    }
    // An ineligible late arrival can enter the lobby, but invalidates readiness.
    for (unsigned n = 2; n <= 4; ++n) {
        Lobby lobby(std::vector<LobbyAccess>(n - 1, testAccess()));
        require(lobby.peers[0]->configureRules(rules), "Eligible rule setup failed");
        until([&] {
            lobby.poll();
            return std::all_of(lobby.peers.begin(), lobby.peers.end(),
                               [&](const auto& peer) { return peer->rules() == rules; });
        });
        lobby.chooseAll(23);
        lobby.add(basic);
        for (unsigned i = 0; i < n; ++i) {
            require(!lobby.peers[0]->choices()[i].ready, "Late locked arrival retained readiness");
            require(!lobby.peers[i]->choose({23, true}), "Locked lobby accepted ready");
        }
        Start start;
        start.seed = "YV039KQF";
        start.rules = rules;
        start.characters.fill(23);
        require(!lobby.peers[0]->start(start), "Late locked arrival started rules");
        require(lobby.peers[0]->configureRules({}), "Cannot return to ordinary rules");
        until([&] {
            lobby.poll();
            return std::all_of(lobby.peers.begin(), lobby.peers.end(),
                               [](const auto& peer) { return peer->rules().id == 0; });
        });
        require(lobby.peers[0]->choices()[n - 1].character == 0 &&
                    lobby.peers.back()->choices()[n - 1].character == 0,
                "Returning to ordinary rules retained a locked character");
        lobby.chooseAll(0);
    }
    // Compaction must carry the profile with its identity, and erase departed data.
    {
        const LobbyAccess other{{0, 7}, {}, {0, 7}};
        Lobby lobby({testAccess(), basic, other, testAccess()});
        lobby.peers[1]->close();
        lobby.peers[1].reset();
        until([&] {
            lobby.poll();
            return lobby.peers[0]->players() == 3 && lobby.peers[2]->slot() == 1 &&
                   lobby.peers[3]->slot() == 2;
        });
        require(lobby.peers[0]->access()[1] == other &&
                    lobby.peers[0]->access()[2] == testAccess() &&
                    lobby.peers[0]->access()[3] == LobbyAccess{},
                "Lobby compaction moved or retained the wrong profile");
        require(lobby.peers[2]->localAccess() == other && lobby.peers[2]->choose({7, true}),
                "Compacted peer lost its local choice access");
        require(!lobby.peers[2]->choose({23, true}), "Compacted peer inherited departed access");
    }
    // A new connection with the original identity must still qualify for its
    // saved character and rules; an unchanged Session reconnect preserves access.
    for (unsigned n = 2; n <= 4; ++n) {
        Group group(n, 0, "127.0.0.1", rules);
        group.ready();
        group.step(0);
        const auto slot = n - 1;
        const auto identity = group.peers[slot]->identity();
        group.peers[slot]->close();
        group.peers[slot].reset();
        const auto departedMask = ((1u << n) - 1) & ~(1u << slot);
        until([&] {
            group.poll();
            return group.peers[0]->connectedMask() == departedMask;
        });
        require(group.step(1).connected == departedMask,
                "Access rejoin fixture did not disconnect");
        for (unsigned missing = 0; missing < 2; ++missing) {
            auto denied = testAccess();
            if (missing)
                denied.rules.clear();
            else {
                denied.characters.pop_back();
                denied.unlockedCharacters.pop_back();
            }
            TestSession rejected;
            require(rejected.join("127.0.0.1", group.peers[0]->port(), "state-test", identity, {},
                                  denied),
                    "Denied rejoin did not connect");
            until([&] {
                group.poll();
                rejected.poll();
                return rejected.phase() == Phase::failed;
            });
            require(rejected.error().find("unavailable") != std::string::npos,
                    "Rejoin failed for an unrelated reason");
        }
        group.peers[slot] = std::make_unique<TestSession>();
        require(group.peers[slot]->join("127.0.0.1", group.peers[0]->port(), "state-test", identity,
                                        {}, testAccess()),
                "Eligible rejoin failed");
        until([&] {
            group.poll();
            return group.peers[slot]->phase() == Phase::waiting;
        });
        auto checkpoint = group.peers[0]->settings();
        checkpoint.snapshot.resize(123, 42);
        require(group.peers[0]->checkpoint(checkpoint, 2), "Eligible rejoin checkpoint failed");
        until([&] {
            group.poll();
            return group.peers[slot]->phase() == Phase::running;
        });
        require(group.peers[slot]->localAccess() == testAccess(), "Rejoin changed local access");
        require(group.peers[slot]->ready(), "Eligible rejoined engine rejected");
        until([&] {
            group.poll();
            return group.peers[0]->connectedMask() == (1u << n) - 1;
        });
        group.peers[slot]->abort("fixture disconnect");
        until([&] {
            group.peers[0]->poll();
            return group.peers[0]->connectedMask() != (1u << n) - 1;
        });
        require(group.peers[slot]->reconnect(), "Reconnect failed");
        until([&] {
            group.poll();
            return group.peers[slot]->phase() == Phase::waiting;
        });
        require(group.peers[slot]->localAccess() == testAccess(), "Reconnect lost local access");
    }
}
void handshake() {
    TestSession host, rejected;
    require(host.host(0, "supported", {}, testAccess()), "Host failed");
    require(rejected.join("127.0.0.1", host.port(), "incompatible", {}, {}, testAccess()),
            "Connection failed");
    until([&] {
        host.poll();
        rejected.poll();
        return rejected.phase() == Phase::failed;
    });
    require(host.phase() == Phase::lobby && host.players() == 1 && !rejected.error().empty(),
            "Rejected handshake damaged host");
    TestSession guest;
    require(guest.join("127.0.0.1", host.port(), "supported", {}, {}, testAccess()),
            "Valid join after rejection failed");
    until([&] {
        host.poll();
        guest.poll();
        return host.players() == 2 && guest.phase() == Phase::lobby;
    });
    TestSession badAddress, badIdentity;
    require(!badAddress.join("not a host", host.port(), "supported", {}, {}, testAccess()),
            "Invalid host address accepted");
    require(!badIdentity.join("127.0.0.1", host.port(), "supported", "not-an-identity", {},
                              testAccess()),
            "Invalid identity accepted");
}
void hostNames() {
    Group g(2, 0, "localhost");
    g.ready();
    g.step(0);
    const auto identity = g.peers[1]->identity();
    g.peers[1]->abort("hostname reconnection test");
    until([&] {
        g.peers[0]->poll();
        return g.peers[0]->connectedMask() == 1;
    });
    require(g.peers[1]->reconnect(), "Host name reconnect failed");
    until([&] {
        g.poll();
        return g.peers[1]->phase() == Phase::waiting;
    });
    require(g.peers[1]->identity() == identity, "Host name reconnect changed identity");
    TestSession missing;
    require(missing.join("isaac-lan-does-not-exist.invalid", g.peers[0]->port(), "state-test", {},
                         {}, testAccess()),
            "Valid host name syntax rejected");
    until([&] {
        missing.poll();
        return missing.phase() == Phase::failed;
    });
    require(missing.error().find("resolve") != std::string::npos,
            "DNS failure lost its explanation");
    TestSession cancelled;
    require(cancelled.join("localhost", g.peers[0]->port(), "state-test", {}, {}, testAccess()),
            "DNS cancellation setup failed");
    cancelled.close();
    cancelled.poll();
    require(cancelled.phase() == Phase::closed && cancelled.resources().connections == 0,
            "A cancelled DNS request reopened the session");
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
void communication() {
    Group g(3);
    g.ready();
    g.step(0);
    require(!g.peers[1]->sendCommunication(2, "spoof") &&
                !g.peers[1]->sendCommunication(0, std::string(maxCommunicationSize + 1, 'x')),
            "Invalid communication destination or size accepted");
    require(g.peers[1]->sendCommunication(0, "chat") && g.peers[1]->sendIntegration(0, "action"),
            "Independent messages rejected");
    std::optional<IntegrationMessage> message, action;
    until([&] {
        g.poll();
        if (!message)
            message = g.peers[0]->takeCommunication();
        if (!action)
            action = g.peers[0]->takeIntegration();
        return message && action;
    });
    require(message->sender == 1 && message->bytes == "chat" && action->bytes == "action",
            "Communication leaked into Mod action traffic or lost sender");
    require(g.peers[0]->sendCommunication(1, "private"), "Private result rejected");
    message.reset();
    until([&] {
        g.poll();
        message = g.peers[1]->takeCommunication();
        return message.has_value();
    });
    require(message->sender == 0 && message->bytes == "private" && !g.peers[2]->takeCommunication(),
            "Private result leaked to another player");
    require(g.peers[0]->sendCommunication(1, "before-floor"), "Pre-floor chat rejected");
    Stage stage;
    stage.epoch = 1;
    stage.level = 2;
    require(g.peers[0]->beginStage(stage), "Floor failed");
    require(g.peers[0]->sendCommunication(1, "during-floor"), "Loading dropped chat");
    std::vector<std::string> received;
    until([&] {
        g.poll();
        while (auto next = g.peers[1]->takeCommunication())
            received.push_back(next->bytes);
        return received.size() == 2 && g.peers[1]->worldEpoch() == 1;
    });
    require(received == std::vector<std::string>{"before-floor", "during-floor"},
            "World transition merged or cleared communication");
    for (unsigned i = 0; i < maxIntegrationQueue; ++i)
        require(g.peers[0]->sendCommunication(0, "local"), "Local communication filled early");
    require(!g.peers[0]->sendCommunication(0, "overflow"), "Unbounded local communication queue");
    require(g.peers[0]->sendIntegration(0, "still-available"), "Chat exhausted action queue");
    std::puts("PASS communication routing, bounded independent queues and floor survival");
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
    g.peers[2] = std::make_unique<TestSession>();
    require(
        g.peers[2]->join("127.0.0.1", g.peers[0]->port(), "state-test", identity, {}, testAccess()),
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
void wireCompression() {
    StateCompression codec(maxMessageSize);
    for (const auto type : {Message::hello, Message::lobby, Message::start, Message::communication,
                            Message::integration, Message::lifecycle}) {
        Writer message(type);
        message.string(std::string(900, 'x'));
        auto wire = encodeWire(message.bytes, codec);
        require(wire.front() == compressedMessageTag && wire.size() < message.bytes.size() / 4,
                "Variable message bypassed shared compression policy");
        require(decodeWire(wire, codec) == message.bytes, "Message compression changed bytes");
        wire.back() ^= 1;
        rejects([&] { decodeWire(wire, codec); }, "Corrupt compressed message accepted");
    }
    const auto input = inputMessage({7, {}, {}}).bytes;
    require(encodeWire(input, codec) == input, "Small input gained a compression envelope");
    std::vector<std::uint8_t> randomBytes(3000);
    std::mt19937 random(91);
    for (auto& byte : randomBytes)
        byte = static_cast<std::uint8_t>(random());
    randomBytes[0] = static_cast<std::uint8_t>(Message::communication);
    require(encodeWire(randomBytes, codec) == randomBytes,
            "Incompressible message grew on the wire");
    randomBytes.assign(3000, 0);
    randomBytes[0] = static_cast<std::uint8_t>(Message::snapshot);
    require(encodeWire(randomBytes, codec) == randomBytes, "Bulk chunks were compressed twice");
    rejects([&] { decodeWire({&compressedMessageTag, 1}, codec); },
            "Empty compressed envelope accepted");
}
void asyncNetwork() {
    Group g(2);
    g.ready();
    g.step(0);
    WorldState state;
    state.tick = 0;
    state.connected = 3;
    state.bytes.resize(maxWorldSize);
    std::mt19937 random(93);
    for (auto& byte : state.bytes)
        byte = static_cast<std::uint8_t>(random());
    require(g.peers[0]->publish(1, state), "Async world rejected");
    g.peers[0]->poll();
    // No more host polling: compression and every chunk must finish without
    // waiting for the next game frame, even for an incompressible maximum view.
    std::optional<WorldState> received;
    until([&] {
        g.peers[1]->poll();
        require(g.peers[1]->phase() != Phase::failed, g.peers[1]->error().c_str());
        received = g.peers[1]->takeState();
        return received.has_value();
    });
    require(received->bytes == state.bytes, "Background world transfer changed bytes");
    require(g.peers[1]->sendCommunication(0, "without another guest frame"), "Async chat rejected");
    std::optional<IntegrationMessage> chat;
    until([&] {
        g.peers[0]->poll();
        chat = g.peers[0]->takeCommunication();
        return chat.has_value();
    });
    require(chat->bytes == "without another guest frame", "Chat required another producer poll");
    // Guest main thread stays idle; the network thread must answer heartbeats.
    until([&] {
        g.peers[0]->poll();
        return g.peers[0]->latency()[1] >= 0;
    });
    require(g.peers[0]->connectedMask() == 3, "Idle guest main thread stopped the connection");
}
void bulkWorker() {
    const auto main = GetCurrentThreadId();
    WakeEvent started, release;
    BulkWorker worker;
    struct Unblock {
        WakeEvent& event;
        ~Unblock() {
            event.signal();
        }
    } unblock{release};
    auto blocked = worker.submit([&](StateCompression&) {
        started.signal();
        WaitForSingleObject(release.handle(), INFINITE);
        return GetCurrentThreadId();
    });
    require(WaitForSingleObject(started.handle(), 2000) == WAIT_OBJECT_0,
            "Bulk worker did not start");
    std::atomic<unsigned> cancelledCalls{0};
    auto cancelled = worker.submit([&](StateCompression&) { return ++cancelledCalls; });
    cancelled.reset();
    // A blocked bulk job must not hold a session lock or the socket owner.
    asyncNetwork();
    release.signal();
    until([&] { return blocked->ready(); });
    require(blocked->take() != main, "Bulk processing ran on the game thread");
    auto checkpoint = std::vector<std::uint8_t>(maxSnapshotSize, 0x47);
    auto packed = worker.submit(
        [bytes = checkpoint](StateCompression& codec) { return codec.compress(bytes); });
    until([&] { return packed->ready(); });
    auto wire = packed->take();
    require(wire.size() < checkpoint.size() / 100, "Archive bypassed compression");
    auto restored = restoreCheckpoint(worker, wire, snapshotHash(wire));
    until([&] { return restored->ready(); });
    require(restored->take() == checkpoint && cancelledCalls == 0,
            "Archive restore or cancelled task ownership failed");
    auto corrupt = restoreCheckpoint(worker, wire, snapshotHash(wire) ^ 1);
    until([&] { return corrupt->ready(); });
    rejects([&] { corrupt->take(); }, "Corrupted checkpoint accepted");
}
void reliableReceive() {
    ReliableReceiver receiver;
    StartEnvelope start;
    start.size = maxSnapshotSize;
    std::vector<std::uint8_t> bytes(start.size);
    std::mt19937 random(99);
    for (auto& byte : bytes)
        byte = static_cast<std::uint8_t>(random());
    const auto snapshotChunk = [&](std::size_t offset) {
        Writer w(Message::snapshot);
        w.u32(offset);
        w.blob(bulkChunk(bytes, offset));
        return w;
    };
    for (unsigned run = 0; run < 2; ++run) {
        receiver.begin(start);
        std::optional<ReceivedBulk> received;
        for (std::size_t offset = 0; offset < bytes.size(); offset += bulkChunkSize) {
            auto message = snapshotChunk(offset);
            Reader r(std::span(message.bytes).subspan(1));
            received = receiver.snapshot(r);
            require(received.has_value() == (offset + bulkChunkSize >= bytes.size()),
                    "Incomplete checkpoint escaped assembly");
        }
        require(received->checkpoint == bytes, "Maximum checkpoint changed during assembly");
        Stage stage{1, 1, 0, 12, false, {}, {}};
        stage.rewind.assign(bytes.begin(), bytes.begin() + 12007);
        for (std::size_t offset = 0; offset < stage.rewind.size(); offset += bulkChunkSize) {
            auto message = stageMessage(stage, offset);
            Reader r(std::span(message.bytes).subspan(1));
            received = receiver.floor(r);
        }
        require(received && received->stage == stage,
                "Repeated rewind assembly lost owned chunk bytes");
    }
    receiver.begin(start);
    auto first = snapshotChunk(0), next = snapshotChunk(bulkChunkSize);
    Reader firstReader(std::span(first.bytes).subspan(1));
    receiver.snapshot(firstReader);
    receiver.reset();
    Reader nextReader(std::span(next.bytes).subspan(1));
    rejects([&] { receiver.snapshot(nextReader); }, "Cancelled checkpoint accepted old chunks");
    receiver.begin(start);
    Reader gapReader(std::span(next.bytes).subspan(1));
    rejects([&] { receiver.snapshot(gapReader); }, "Out-of-order checkpoint chunk accepted");
    Stage stage{1, 1, 0, 12, false, {}, {}};
    stage.rewind.resize(6001, 1);
    auto chunk = stageMessage(stage);
    Reader stageFirst(std::span(chunk.bytes).subspan(1));
    receiver.floor(stageFirst);
    ++stage.sourceRoom;
    chunk = stageMessage(stage, bulkChunkSize);
    Reader changed(std::span(chunk.bytes).subspan(1));
    rejects([&] { receiver.floor(changed); }, "Mixed rewind metadata accepted");
}
void worldDeltas() {
    Group g(4);
    g.ready();
    std::mt19937 random(73);
    std::array<std::vector<std::uint8_t>, 4> expected;
    std::array<std::vector<std::uint8_t>, 4> dependencies;
    for (unsigned slot = 1; slot < 4; ++slot) {
        expected[slot].resize(140000);
        for (auto& byte : expected[slot])
            byte = static_cast<std::uint8_t>(random());
        dependencies[slot].resize(20000, static_cast<std::uint8_t>(slot));
    }
    std::array<unsigned, 4> received{};
    received.fill(UINT32_MAX);
    for (unsigned tick = 0; tick < 100; ++tick) {
        g.step(tick);
        for (unsigned slot = 1; slot < 4; ++slot) {
            expected[slot][200 + tick] ^= static_cast<std::uint8_t>(tick + slot);
            if (tick == 30)
                expected[slot].insert(expected[slot].begin() + 4000, 913, 0x42);
            if (tick == 60)
                expected[slot].erase(expected[slot].begin() + 7000, expected[slot].begin() + 8013);
            WorldState state;
            state.tick = tick;
            state.connected = 15;
            state.bytes = expected[slot];
            if (tick % 10 == 0)
                dependencies[slot][tick] = static_cast<std::uint8_t>(tick + slot);
            state.stable = dependencies[slot];
            require(g.peers[0]->publish(slot, state), "Delta publication failed");
        }
        // Leave one guest unacknowledged while other players keep consuming.
        until([&] {
            g.poll();
            for (unsigned slot = 1; slot < 3; ++slot)
                if (auto state = g.peers[slot]->takeState()) {
                    require(state->bytes == expected[slot], "Delta changed a complete view");
                    require(state->stable == dependencies[slot],
                            "Realtime view used the wrong reliable dependency revision");
                    g.peers[slot]->applied(state->tick);
                    received[slot] = state->tick;
                }
            return received[1] == tick && received[2] == tick;
        });
        const auto resources = g.peers[0]->resources();
        require(resources.inFlightStates <= 3 * 16 &&
                    resources.cachedWorldBytes <= 3 * 8 * maxWorldSize,
                "Unacknowledged peer grew an unbounded delta cache");
    }
    until([&] {
        g.poll();
        if (auto state = g.peers[3]->takeState()) {
            g.peers[3]->applied(state->tick);
            received[3] = state->tick;
            if (state->tick == 99)
                require(state->bytes == expected[3], "Coalescing lost the latest full view");
        }
        return received[3] == 99;
    });
    const auto resources = g.peers[0]->resources();
    require(resources.deltaSnapshots > 180 &&
                resources.wireWorldBytes < resources.fullWorldBytes / 2,
            "Confirmed sparse snapshots did not reduce actual compressed traffic");
    std::printf("DELTA snapshots=%llu deltas=%llu full_wire=%llu actual_wire=%llu\n",
                static_cast<unsigned long long>(resources.worldSnapshots),
                static_cast<unsigned long long>(resources.deltaSnapshots),
                static_cast<unsigned long long>(resources.fullWorldBytes),
                static_cast<unsigned long long>(resources.wireWorldBytes));
}
void deliveryBackpressure() {
    Group group(3);
    group.ready();
    std::uint32_t sequence = 0;
    auto step = [&](bool slowReceipt, bool waitSlowDelivery = false) {
        const auto tick = group.step(sequence++).tick;
        group.publish(tick);
        bool healthy = false, recoveredPeer = !(slowReceipt || waitSlowDelivery);
        until([&] {
            group.poll();
            if (slowReceipt || waitSlowDelivery)
                if (auto state = group.peers[1]->takeState()) {
                    if (slowReceipt)
                        group.peers[1]->applied(state->tick);
                    recoveredPeer = state->tick == tick;
                }
            if (auto state = group.peers[2]->takeState()) {
                group.peers[2]->applied(state->tick);
                healthy = state->tick == tick;
            }
            return healthy && recoveredPeer;
        });
        return tick;
    };
    for (unsigned i = 0; i < 20; ++i) {
        step(false);
        Sleep(20);
    }
    const auto stalled = group.peers[0]->resources();
    require(stalled.inFlightStates <= 8 && stalled.oldestWorldMs >= 300,
            "Stalled application receipts were unbounded or not exercised");
    // Retire the delayed views. Refilling remains bounded while the other
    // guest has continued receiving every tick.
    step(true);
    until([&] {
        group.poll();
        return group.peers[0]->resources().inFlightStates == 0;
    });
    const auto before = group.peers[0]->resources().worldSnapshots;
    for (unsigned i = 0; i < 10; ++i)
        step(false);
    group.poll();
    const auto throttled = group.peers[0]->resources();
    require(throttled.worldSnapshots - before <=
                10 + WorldTransfer::window(group.peers[0]->latency()[1]),
            "Delayed receipt refilled an unbounded stale-state window");
    // Reliable lifecycle messages must still progress through the same UDP
    // connection while ordinary world publication is throttled.
    const Stage stage{1, 2, 0, 0, false, {}, {}};
    require(group.peers[0]->beginStage(stage), "Congestion blocked a floor event");
    std::array<bool, 3> arrived{};
    until([&] {
        group.poll();
        for (unsigned slot = 1; slot < 3; ++slot)
            if (auto event = group.peers[slot]->takeStage()) {
                require(*event == stage, "Throttled floor event changed");
                arrived[slot] = true;
            }
        return arrived[1] && arrived[2];
    });
    for (unsigned i = 0; i < 24; ++i)
        step(true);
    until([&] {
        group.poll();
        return group.peers[0]->resources().inFlightStates == 0;
    });
    const auto recovered = group.peers[0]->resources().worldSnapshots;
    for (unsigned i = 0; i < 10; ++i)
        // Observe delivery without acknowledging the first four states. Fast
        // publication alone may legitimately replace unscheduled latest views.
        step(false, i < 4);
    until([&] {
        group.poll();
        return group.peers[0]->resources().worldSnapshots - recovered >= 14;
    });
}
void deltaFloorBoundary() {
    Group g(2);
    g.ready();
    g.step(0);
    g.publish(0);
    until([&] {
        g.poll();
        if (auto state = g.peers[1]->takeState()) {
            g.peers[1]->applied(state->tick);
            return true;
        }
        return false;
    });
    require(g.peers[0]->beginStage({2, 2, 0, 0, false, {}, {}}), "Delta floor reset failed");
    g.step(1);
    g.publish(1);
    until([&] {
        g.poll();
        if (auto state = g.peers[1]->takeState()) {
            require(state->epoch == 2 && state->tick == 1, "An old delta crossed a floor boundary");
            g.peers[1]->applied(state->tick);
            return true;
        }
        return false;
    });
    require(g.peers[0]->resources().deltaSnapshots == 0, "New floor reused a retired baseline");
    g.step(2);
    g.publish(2);
    until([&] {
        g.poll();
        if (auto state = g.peers[1]->takeState()) {
            g.peers[1]->applied(state->tick);
            return state->tick == 2;
        }
        return false;
    });
}
} // namespace
void resourceLifecycle() {
    const auto retained = [] {
        PROCESS_MEMORY_COUNTERS_EX value{};
        value.cb = sizeof(value);
        require(GetProcessMemoryInfo(GetCurrentProcess(),
                                     reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&value),
                                     sizeof(value)),
                "Cannot inspect private memory");
        return value.PrivateUsage;
    };
    const auto handles = [] {
        DWORD value = 0;
        require(GetProcessHandleCount(GetCurrentProcess(), &value), "Cannot inspect handle count");
        return value;
    };
    const auto cycle = [] {
        Group g(2);
        g.ready();
        for (unsigned tick = 0; tick < 128; ++tick) {
            g.step(tick);
            g.publish(tick, 65536);
            if (tick % 16 == 0) {
                g.poll();
                g.peers[1]->takeState();
            }
            const auto resources = g.peers[0]->resources();
            require(resources.queuedBytes <= 262144 * 4 &&
                        resources.worldBytes <= 2 * maxWorldSize * 4 &&
                        resources.cachedWorldBytes <= 8 * maxWorldSize * 4,
                    "Slow consumer accumulated unbounded queues or views");
        }
        for (auto& peer : g.peers) {
            if (!peer)
                continue;
            peer->close();
            const auto closed = peer->resources();
            require(closed.connections == 0 && closed.queuedBytes == 0 &&
                        closed.cachedWorldBytes == 0 && closed.inFlightBytes == 0 &&
                        closed.inFlightStates == 0,
                    "Closed transport retained sockets, queues or delta history");
        }
    };
    for (unsigned warm = 0; warm < 5; ++warm)
        cycle();
    const auto beforeHandles = handles();
    const auto beforeMemory = retained();
    for (unsigned i = 0; i < 40; ++i)
        cycle();
    require(handles() <= beforeHandles + 2, "Repeated sessions leaked process handles");
    require(retained() <= beforeMemory + 8 * 1024 * 1024,
            "Warm repeated sessions retained over 8 MiB; inspect the resource report");
    std::printf("RESOURCE cycles=45 snapshots=5760 private_before=%llu private_after=%llu "
                "handles_before=%lu handles_after=%lu\n",
                static_cast<unsigned long long>(beforeMemory),
                static_cast<unsigned long long>(retained()), beforeHandles, handles());
}
int main(int argc, char** argv) {
    if (argc == 2 && (std::string_view(argv[1]) == "udp-loss" ||
                      std::string_view(argv[1]) == "udp-large-recovery"))
        return runTests(
            argc, argv,
            {{"udp-loss", udpLossRecovery}, {"udp-large-recovery", udpFragmentedRecovery}});
    const auto result = runTests(argc, argv,
                                 {{"codec", codec},
                                  {"world-deltas", worldDeltas},
                                  {"wire-compression", wireCompression},
                                  {"async-network", asyncNetwork},
                                  {"bulk-worker", bulkWorker},
                                  {"reliable-receive", reliableReceive},
                                  {"delivery-backpressure", deliveryBackpressure},
                                  {"delta-floor-boundary", deltaFloorBoundary},
                                  {"compression-limits", compressionLimits},
                                  {"render-inputs", renderInputs},
                                  {"input-backpressure", inputBackpressure},
                                  {"inputs-2", [] { inputsAndStates(2); }},
                                  {"inputs-3", [] { inputsAndStates(3); }},
                                  {"inputs-4", [] { inputsAndStates(4); }},
                                  {"floor-rejoin", floorRejoin},
                                  {"stage-events", stageEvents},
                                  {"ending-events", endingEvents},
                                  {"ending-liveness", endingLiveness},
                                  {"restart", restartRuns},
                                  {"return-lobby", returnLobby},
                                  {"cinematic-events", cinematicEvents},
                                  {"stage-during-rejoin", stageDuringRejoin},
                                  {"rewind", rewindTransaction},
                                  {"progression", progression},
                                  {"r-key", rKeyTransaction},
                                  {"room-commands", roomCommands},
                                  {"input-rooms", inputRooms},
                                  {"lobby", lobby},
                                  {"run-rules", runRules},
                                  {"room-options", roomOptions},
                                  {"lobby-access", lobbyAccess},
                                  {"handshake", handshake},
                                  {"host-names", hostNames},
                                  {"commands", commands},
                                  {"loading-exit", loadingExit},
                                  {"loading-timeout", loadingTimeout},
                                  {"publication-limits", publicationLimits},
                                  {"integrations", integrations},
                                  {"communication", communication},
                                  {"greed-settings", greedSettings},
                                  {"host-disconnect", hostDisconnect},
                                  {"resource-lifecycle", resourceLifecycle}});
    if (!result)
        std::puts("ALL STATE TRANSPORT TESTS PASSED");
    return result;
}

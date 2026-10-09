#include "net_protocol.h"
#include "automation_input.h"
#include "lanbot_console.h"
#include "progression.h"
#include "session_archive.h"
#include "test_support.h"
#include <algorithm>
#include <limits>

using namespace isaac::lan;

namespace {
void automationInput() {
    using isaac::input::botConsoleArguments;
    require(botConsoleArguments("lanbot") == std::string_view{} &&
                botConsoleArguments("lanbot on") == "on" &&
                botConsoleArguments("lanbot\tmode hold") == "mode hold",
            "Native console must forward complete LANBOT arguments, including bare help");
    require(!botConsoleArguments("lanbotscript on") && !botConsoleArguments("lua lanbot on") &&
                !botConsoleArguments("spawn 5.100.1") && !botConsoleArguments(""),
            "Native LANBOT dispatch must preserve other console commands");
    isaac::input::AutomationInput bot;
    InputFrame manual;
    manual.values[0] = 65535;
    manual.values[8] = 42000;
    manual.values[13] = 65535;
    manual.triggered = (1u << 0) | (1u << 8) | (1u << 13);
    require(bot.compose(manual, 10, true).values == manual.values, "Disabled bot changed input");
    bot.set(true, 2 | 32, 10);
    auto preview = bot.compose(manual, 10, false);
    require(preview.values[0] == 0 && preview.values[1] == 65535 && preview.values[5] == 65535,
            "Bot must replace, rather than merge, manual movement and shooting");
    require(preview.values[8] == 42000 && preview.values[13] == 65535 &&
                preview.triggered == ((1u << 1) | (1u << 5) | (1u << 8) | (1u << 13)),
            "Automation changed manual UI or consumable input");
    auto captured = bot.compose(manual, 10, true);
    require(captured.values == preview.values && captured.triggered == preview.triggered,
            "Prediction consumed edges or disagreed with capture");
    bot.set(true, 2 | 32, 11);
    require((bot.compose(manual, 11, true).triggered & 255) == 0, "Held bot input repeated edges");
    bot.set(true, 0, 12);
    bot.set(true, 64, 13);
    bot.set(true, 0, 14);
    captured = bot.compose(manual, 14, true);
    require(captured.values[6] == 0 && (captured.triggered & 255) == 64,
            "Short bot press between network samples was lost");
    bot.set(true, 128, 15);
    captured = bot.compose(manual, 19, true);
    require(captured.values[0] == 0 && captured.values[7] == 0 && (captured.triggered & 255) == 0,
            "Expired decisions must release gameplay controls while retaining ownership");
    bot.set(true, 1, 20);
    bot.set(false, 0, 20);
    captured = bot.compose(manual, 20, true);
    require(captured.values == manual.values && captured.triggered == manual.triggered,
            "Pause/off must discard bot edges and restore manual input");
    bot.set(true, 4, std::numeric_limits<std::uint32_t>::max());
    require(bot.compose({}, 1, false).values[2] == 65535, "Frame counter wrap expired fresh input");
    require(bot.compose({}, 3, false).values[2] == 0, "Frame counter wrap retained stale input");
    bot.clear();
    require(bot.compose(manual, 4, true).values == manual.values,
            "Session reset retained bot input");
}
void integers() {
    Writer w(Message::input);
    w.u8(0xff);
    w.u16(0x1234);
    w.u32(0x89abcdef);
    w.u64(0x0123456789abcdef);
    const std::vector<std::uint8_t> expected{5,    0xff, 0x12, 0x34, 0x89, 0xab, 0xcd, 0xef,
                                             0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef};
    require(w.bytes == expected, "Integers must use network byte order");
    Reader r(w.bytes);
    require(r.u8() == 5 && r.u8() == 0xff && r.u16() == 0x1234 && r.u32() == 0x89abcdef &&
                r.u64() == 0x0123456789abcdef,
            "Integer round trip failed");
    r.finish();
}

void stringsAndBlobs() {
    Writer w(Message::world);
    const std::string text("a\0b", 3);
    const std::string maximum(1024, 'x');
    const std::vector<std::uint8_t> bytes{0, 1, 0xff};
    w.string("");
    w.string(text);
    w.string(maximum);
    w.blob({});
    w.blob(bytes);
    Reader r(w.bytes);
    r.u8();
    require(r.string().empty() && r.string() == text && r.string() == maximum,
            "String round trip failed");
    require(r.blob().empty() && r.blob(3) == bytes, "Blob round trip failed");
    r.finish();
    rejects([&] { w.string(std::string(1025, 'x')); }, "Oversized string accepted");
    rejects([&] { w.blob(std::vector<std::uint8_t>(maxSnapshotSize + 1)); },
            "Oversized blob accepted");
    Writer limit(Message::world);
    limit.blob(bytes);
    rejects(
        [&] {
            Reader small(limit.bytes);
            small.u8();
            small.blob(2);
        },
        "Caller blob limit ignored");
    Writer malformed(Message::world);
    malformed.u16(1025);
    rejects(
        [&] {
            Reader invalid(malformed.bytes);
            invalid.u8();
            invalid.string();
        },
        "Oversized string header accepted");
    Writer oversized(Message::world);
    oversized.u32(maxSnapshotSize + 1);
    rejects(
        [&] {
            Reader invalid(oversized.bytes);
            invalid.u8();
            invalid.blob();
        },
        "Oversized blob header accepted");
}

void inputAndProgress() {
    InputFrame input;
    input.triggered = 0xa55a;
    for (unsigned i = 0; i < input.values.size(); ++i)
        input.values[i] = i * 4096;
    Progress progress;
    progress.achievements.front() = progress.achievements.back() = 1;
    progress.counters.front() = 0xffffffff;
    progress.counters.back() = 0x80000000;
    Writer w(Message::input);
    w.input(input);
    w.progress(std::nullopt);
    w.progress(progress);
    Reader r(w.bytes);
    r.u8();
    require(r.input() == input && !r.progress() && r.progress() == progress,
            "Input or progress round trip failed");
    r.finish();
    Writer invalid(Message::input);
    invalid.u8(2);
    rejects(
        [&] {
            Reader reader(invalid.bytes);
            reader.u8();
            reader.progress();
        },
        "Invalid presence flag accepted");
    invalid.bytes.resize(1);
    progress.achievements[17] = 2;
    invalid.progress(progress);
    rejects(
        [&] {
            Reader reader(invalid.bytes);
            reader.u8();
            reader.progress();
        },
        "Invalid achievement flag accepted");
}

void truncatedPackets() {
    Writer w(Message::world);
    w.u64(42);
    w.string("test");
    w.input({});
    w.progress(Progress{});
    w.blob({});
    for (std::size_t length = 0; length < w.bytes.size(); ++length) {
        rejects(
            [&] {
                Reader r(std::span(w.bytes).first(length));
                r.u8();
                r.u64();
                r.string();
                r.input();
                r.progress();
                r.blob();
                r.finish();
            },
            "Truncated packet accepted");
    }
    w.u8(0);
    rejects(
        [&] {
            Reader r(w.bytes);
            r.u8();
            r.u64();
            r.string();
            r.input();
            r.progress();
            r.blob();
            r.finish();
        },
        "Trailing protocol data accepted");
}

void hashes() {
    require(snapshotHash({}) == 0xcbf29ce484222325, "Empty FNV-1a hash differs");
    const std::vector<std::uint8_t> hello{'h', 'e', 'l', 'l', 'o'};
    require(snapshotHash(hello) == 0xa430d84680aabd0b, "FNV-1a reference vector differs");
}

void progression() {
    Progress local, common, current;
    local.achievements[7] = 1;
    common.achievements[9] = 1;
    current = common;
    current.achievements[11] = 1;
    local.counters[0] = 12;
    common.counters[0] = 1000;
    current.counters[0] = 1003;
    local.counters[1] = 2;
    common.counters[1] = 10;
    current.counters[1] = 0;
    local.counters[2] = std::numeric_limits<std::int32_t>::max() - 1;
    current.counters[2] = 10;
    local.counters[3] = 50;
    common.counters[3] = 100;
    current.counters[3] = 93;
    const auto merged = mergeProgress(local, common, current);
    require(merged.achievements[7] && !merged.achievements[9] && merged.achievements[11],
            "Shared achievements leaked into local progress");
    require(merged.counters[0] == 15 && merged.counters[1] == 0 &&
                merged.counters[2] == std::numeric_limits<std::int32_t>::max() &&
                merged.counters[3] == 43,
            "Counter delta or saturation failed");
    require(mergeProgress(local, common, common) == local, "No-op session changed local progress");
}

Archive sample(unsigned players = 4) {
    Archive value;
    value.fingerprint = "test-build";
    value.settings.seed = "YV039KQF";
    value.settings.difficulty = 3;
    value.settings.characters = {0, 1, 37, 65535};
    value.settings.progress = Progress{};
    value.settings.progress->achievements[42] = 1;
    value.settings.progress->counters[17] = 1234;
    for (unsigned i = 0; i < players; ++i)
        value.locations.push_back(
            {static_cast<int>(i % 3), -20 + static_cast<int>(i), 12.5f, -4.25f});
    value.game.resize(6507);
    for (unsigned i = 0; i < value.game.size(); ++i)
        value.game[i] = static_cast<std::uint8_t>(i);
    return value;
}

void archiveRoundTrip() {
    for (unsigned players = 2; players <= 4; ++players) {
        auto value = sample(players);
        if (players == 2)
            value.settings.progress.reset();
        const auto decoded = Archive::decode(value.encode());
        require(decoded.fingerprint == value.fingerprint &&
                    decoded.settings.seed == value.settings.seed &&
                    decoded.settings.difficulty == value.settings.difficulty &&
                    decoded.settings.characters == value.settings.characters &&
                    decoded.settings.progress == value.settings.progress &&
                    decoded.game == value.game,
                "Saved session round trip failed");
        require(decoded.locations.size() == players, "Saved roster differs");
        for (unsigned i = 0; i < players; ++i) {
            const auto& actual = decoded.locations[i];
            const auto& expected = value.locations[i];
            require(actual.dimension == expected.dimension && actual.index == expected.index &&
                        actual.x == expected.x && actual.y == expected.y,
                    "Saved player location differs");
        }
    }
}

void archiveIntegrity() {
    const auto bytes = sample().encode();
    for (std::size_t length = 0; length < bytes.size(); ++length)
        rejects([&] { Archive::decode(std::span(bytes).first(length)); },
                "Truncated saved session accepted");
    auto corrupt = bytes;
    corrupt[100] ^= 1;
    rejects([&] { Archive::decode(corrupt); }, "Corrupted saved session accepted");
    corrupt = bytes;
    corrupt.back() ^= 1;
    rejects([&] { Archive::decode(corrupt); }, "Invalid saved checksum accepted");
    // Recompute the checksum to exercise the schema validation independently.
    corrupt = bytes;
    corrupt.resize(corrupt.size() - 8);
    corrupt.push_back(0);
    Writer checksum(Message::snapshot);
    checksum.bytes = corrupt;
    checksum.u64(snapshotHash(corrupt));
    rejects([&] { Archive::decode(checksum.bytes); }, "Trailing saved session data accepted");
    corrupt = bytes;
    corrupt[0] = static_cast<std::uint8_t>(Message::world);
    corrupt.resize(corrupt.size() - 8);
    checksum.bytes = corrupt;
    checksum.u64(snapshotHash(corrupt));
    rejects([&] { Archive::decode(checksum.bytes); }, "Invalid saved message type accepted");
    corrupt = bytes;
    corrupt[17] = '3';
    corrupt.resize(corrupt.size() - 8);
    checksum.bytes = corrupt;
    checksum.u64(snapshotHash(corrupt));
    rejects([&] { Archive::decode(checksum.bytes); }, "Unsupported save version accepted");
    rejects([&] { Archive::decode(std::vector<std::uint8_t>(maxSnapshotSize + 1)); },
            "Oversized saved session accepted");
}

void archiveSettings() {
    for (unsigned players : {0, 1, 5}) {
        const auto value = sample(players);
        rejects([&] { Archive::decode(value.encode()); }, "Invalid saved roster accepted");
    }
    auto value = sample();
    value.settings.seed = "short";
    rejects([&] { Archive::decode(value.encode()); }, "Invalid saved seed accepted");
    value = sample();
    value.settings.difficulty = 4;
    rejects([&] { Archive::decode(value.encode()); }, "Invalid saved difficulty accepted");
}

void archiveLocations() {
    for (const auto location : std::initializer_list<isaac::rooms::SavedLocation>{
             {-1, 0, 0, 0},
             {3, 0, 0, 0},
             {0, -21, 0, 0},
             {0, 169, 0, 0},
             {0, 0, 10001, 0},
             {0, 0, 0, -10001},
             {0, 0, std::numeric_limits<float>::infinity(), 0},
             {0, 0, 0, std::numeric_limits<float>::quiet_NaN()}}) {
        auto value = sample();
        value.locations[0] = location;
        rejects([&] { Archive::decode(value.encode()); }, "Invalid saved location accepted");
    }
    auto value = sample();
    value.locations[0] = {2, 168, 10000, -10000};
    require(Archive::decode(value.encode()).locations[0].index == 168,
            "Valid saved location boundary rejected");
}
} // namespace

int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"integers", integers},
                     {"strings-blobs", stringsAndBlobs},
                     {"input-progress", inputAndProgress},
                     {"automation-input", automationInput},
                     {"truncated-packets", truncatedPackets},
                     {"hashes", hashes},
                     {"progression", progression},
                     {"archive-round-trip", archiveRoundTrip},
                     {"archive-integrity", archiveIntegrity},
                     {"archive-settings", archiveSettings},
                     {"archive-locations", archiveLocations}});
}

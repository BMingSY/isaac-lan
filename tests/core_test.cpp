#include "net_protocol.h"
#include "automation_input.h"
#include "menu_input.h"
#include "bootstrap_profile.h"
#include "lanbot_console.h"
#include "progression.h"
#include "session_archive.h"
#include "intro_barrier.h"
#include "room_map.h"
#include "test_support.h"
#include <algorithm>
#include <limits>

using namespace isaac::lan;

namespace {
void transitionCharge() {
    InputFrame held;
    held.values.fill(65535);
    held.triggered = 0xffff;
    const auto transfer = isaac::input::transitionInput(held, true);
    for (unsigned action = 0; action < actionCount; ++action)
        require(transfer.values[action] ==
                    ((action >= 4 && action < 8) || action == 12 || action == 15 ? 65535 : 0),
                "Room transfer released charge or retained movement/item controls");
    require(transfer.triggered == menuActionMask, "Transfer replayed a gameplay edge");
    require(isaac::input::transitionInput({}, true).values[4] == 0,
            "Real shooting release was swallowed");
    require(isaac::input::transitionInput(held, false) == menuInput(held),
            "Previous-floor fire leaked into the new floor");
    const InputRoom source{7, 84, 0}, destination{8, 85, 0};
    std::optional<InputRoom> previous = source, room;
    auto loading = held;
    isaac::input::captureRoomInput(loading, room, previous, 7);
    require(room == source && loading == transfer,
            "Scoped room loading synthesized a charged-weapon release");
    room.reset();
    loading = {};
    isaac::input::captureRoomInput(loading, room, previous, 7);
    require(room == source && loading == InputFrame{}, "Loading swallowed a real fire release");
    room.reset();
    loading = held;
    isaac::input::captureRoomInput(loading, room, previous, 8);
    require(!room && loading == menuInput(held), "Previous-floor room was reused while loading");
    room = destination;
    loading = held;
    isaac::input::captureRoomInput(loading, room, previous, 8);
    require(previous == destination && loading == held,
            "Stable destination did not restore full native controls");
}
void bootstrapProfile() {
    using isaac::bootstrap::Profile;
    using isaac::bootstrap::profile;
    require(profile(true, true, false, false) == Profile::installed,
            "Steam inherited a lab root and blocked the installed game");
    require(profile(true, false, false, false) == Profile::installed,
            "Ordinary installed launch lost its real profile");
    for (bool installed : {false, true}) {
        require(profile(installed, true, true, true) == Profile::isolated,
                "A genuine lab launch escaped profile isolation");
        require(profile(installed, true, true, false) == Profile::missingMarker,
                "An unmarked lab executable fell back to the real profile");
    }
    require(profile(false, true, false, true) == Profile::wrongPath,
            "Foreign lab environment authorized an uninstalled executable");
    require(profile(false, false, false, false) == Profile::missingMarker,
            "Unmarked executable was permitted to bootstrap");
}
void keyboardPause() {
    InputFrame escape;
    escape.values[15] = 65535;
    escape.triggered = 1u << 15;
    auto menu = escape;
    const auto original = menu;
    isaac::input::keyboardPause(escape, false);
    require(escape.triggered == ((1u << 12) | (1u << 15)) && escape.values[12] == 65535,
            "Keyboard Escape cannot open pause on a LAN controller");
    isaac::input::keyboardPause(menu, true);
    require(menu == original, "Escape changed native menu navigation");
    require(menu.values[12] == 0, "Menu Back became another pause press");
    menu.triggered = 0;
    isaac::input::keyboardPause(menu, false);
    require(menu.triggered == 0 && menu.values[12] == 0,
            "Held Escape created a repeated pause edge");
}
void roomMap() {
    std::array<int, 507> offsets;
    offsets.fill(-1);
    unsigned count = 20;
    const std::array<unsigned, 2> cells{98, 99};
    isaac::rooms::registerMapRoom(offsets, count, 0, 98, 20, cells);
    require(offsets[98] == 20 && offsets[99] == 20 && offsets[97] == -1 && count == 21,
            "Generated room was absent from the native minimap index");
    isaac::rooms::registerMapRoom(offsets, count, 1, 98, 22, cells);
    require(offsets[98] == 20 && offsets[169 + 98] == 22 && count == 23,
            "Room registration crossed dimensions");
    const auto before = offsets;
    for (const auto invalid : {std::array<unsigned, 2>{98, 169}, std::array<unsigned, 2>{97, 99}}) {
        bool failed = false;
        try {
            isaac::rooms::registerMapRoom(offsets, count, 0, 98, 24, invalid);
        } catch (const std::runtime_error&) {
            failed = true;
        }
        require(failed && offsets == before && count == 23,
                "Invalid map aliases partially changed the floor");
    }
}
void introBarrier() {
    isaac::presentation::IntroBarrier barrier;
    const std::array room{1, 0, 0, 84}, other{1, 0, 0, 85};
    barrier.start(room, 1, 100, 1);
    require(barrier.paused(room, 110, 15) && !barrier.paused(other, 110, 15),
            "Host intro must pause only the boss room");
    barrier.observe(0, 1, false);
    require(!barrier.paused(room, 111, 15), "Completed host intro kept its room frozen");
    barrier.start(room, 2, 100, 7);
    require(barrier.paused(room, 110, 7) && !barrier.paused(other, 110, 7),
            "Intro froze an unrelated room");
    barrier.observe(1, 1, false);
    barrier.observe(2, 2, true);
    require(barrier.paused(room, 120, 7), "Stale or active intro released combat");
    barrier.observe(1, 2, false);
    barrier.observe(0, 2, false);
    require(barrier.paused(room, 130, 7), "Combat resumed before every guest finished");
    barrier.observe(2, 2, false);
    require(!barrier.paused(room, 140, 7), "Finished intro kept combat frozen");
    barrier.start(room, 3, 150, 3);
    barrier.observe(0, 3, false);
    require(!barrier.paused(room, 160, 1), "Disconnected guest froze combat");
    barrier.start(room, 4, 200, 3);
    require(!barrier.paused(room, 801, 3), "Missing acknowledgement froze combat indefinitely");
    barrier.start(room, 5, 900, 3);
    barrier.clear();
    require(!barrier.paused(room, 901, 3), "Session reset retained an intro");
}
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
    const auto menu = menuInput(input);
    require(menu.triggered == (input.triggered & menuActionMask) &&
                menu.values[12] == input.values[12] && menu.values[15] == input.values[15],
            "Room filtering discarded session menu actions");
    for (unsigned i = 0; i < actionCount; ++i)
        if (i != 12 && i != 15)
            require(menu.values[i] == 0, "Room filtering retained a gameplay action");
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
                     {"keyboard-pause", keyboardPause},
                     {"transition-charge", transitionCharge},
                     {"bootstrap-profile", bootstrapProfile},
                     {"intro-barrier", introBarrier},
                     {"room-map", roomMap},
                     {"truncated-packets", truncatedPackets},
                     {"hashes", hashes},
                     {"progression", progression},
                     {"archive-round-trip", archiveRoundTrip},
                     {"archive-integrity", archiveIntegrity},
                     {"archive-settings", archiveSettings},
                     {"archive-locations", archiveLocations}});
}

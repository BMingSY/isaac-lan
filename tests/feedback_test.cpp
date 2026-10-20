#include "core/feedback.h"
#include "miniz.h"
#include "test_support.h"
#include <array>
#include <cstring>
#include <map>
#include <random>
#include <string>

namespace {
namespace feedback = isaac::feedback;

std::uint32_t read16(const std::vector<std::uint8_t>& bytes, std::size_t at) {
    require(at + 2 <= bytes.size(), "Zip field is out of range");
    return bytes[at] | bytes[at + 1] << 8;
}
std::uint32_t read32(const std::vector<std::uint8_t>& bytes, std::size_t at) {
    return read16(bytes, at) | read16(bytes, at + 2) << 16;
}
struct Entry {
    std::vector<std::uint8_t> data;
    std::uint32_t flags, method;
};
// Independent reader: walks the end record and central directory, then
// checks each local header, decompresses and verifies the CRC.
std::map<std::string, Entry> unzip(const std::vector<std::uint8_t>& bytes) {
    require(bytes.size() >= 22, "Zip is too short");
    const auto end = bytes.size() - 22;
    require(read32(bytes, end) == 0x06054b50, "Missing end of central directory");
    const auto count = read16(bytes, end + 10);
    auto at = static_cast<std::size_t>(read32(bytes, end + 16));
    require(at + read32(bytes, end + 12) == end, "Central directory size or offset is wrong");
    std::map<std::string, Entry> entries;
    for (std::uint32_t i = 0; i < count; ++i) {
        require(read32(bytes, at) == 0x02014b50, "Missing central header");
        const auto flags = read16(bytes, at + 8), method = read16(bytes, at + 10);
        const auto crc = read32(bytes, at + 16), packed = read32(bytes, at + 20),
                   size = read32(bytes, at + 24);
        const auto nameLength = read16(bytes, at + 28);
        const auto local = read32(bytes, at + 42);
        const std::string name(bytes.begin() + at + 46, bytes.begin() + at + 46 + nameLength);
        at += 46 + nameLength;
        require(read32(bytes, local) == 0x04034b50, "Missing local header");
        require(read16(bytes, local + 6) == flags && read16(bytes, local + 8) == method &&
                    read32(bytes, local + 14) == crc && read32(bytes, local + 18) == packed &&
                    read32(bytes, local + 22) == size && read16(bytes, local + 26) == nameLength,
                "Local header disagrees with central header");
        const auto data = local + 30 + nameLength + read16(bytes, local + 28);
        require(data + packed <= bytes.size(), "Compressed data is out of range");
        std::vector<std::uint8_t> content;
        if (method == 0) {
            content.assign(bytes.begin() + data, bytes.begin() + data + packed);
        } else {
            require(method == 8, "Unexpected compression method");
            std::size_t length = 0;
            auto* output = static_cast<std::uint8_t*>(
                tinfl_decompress_mem_to_heap(bytes.data() + data, packed, &length, 0));
            require(output != nullptr, "Raw deflate data did not decode");
            content.assign(output, output + length);
            mz_free(output);
        }
        require(content.size() == size, "Decoded size mismatch");
        require(mz_crc32(MZ_CRC32_INIT, content.data(), content.size()) == crc, "CRC mismatch");
        entries[name] = {std::move(content), flags, method};
    }
    require(at == end, "Trailing bytes after central directory");
    return entries;
}
std::vector<std::uint8_t> bytes(std::string_view text) {
    return {text.begin(), text.end()};
}

void zipLayout() {
    std::mt19937 random(7);
    std::vector<std::uint8_t> noise(70000);
    for (auto& byte : noise)
        byte = static_cast<std::uint8_t>(random());
    std::string repeated;
    for (int i = 0; i < 4000; ++i)
        repeated += "INFO room_enter index=" + std::to_string(i % 13) + "\n";
    const std::vector<feedback::File> files = {
        {"feedback.json", bytes("{\"schema\":1}")},
        {"logs/20261021-101500-123-p42/startup.log", bytes(repeated)},
        {"logs/empty.log", {}},
        {"game/noise.bin", noise},
        {"mods/中文.txt", bytes("名称")},
    };
    const auto archive = feedback::zip(files, 0x5000, 0x5955);
    const auto entries = unzip(archive);
    require(entries.size() == files.size(), "Entry count mismatch");
    for (const auto& file : files)
        require(entries.at(file.name).data == file.data, "Entry content mismatch");
    const std::vector<feedback::File> log = {{"startup.log", bytes(repeated)}};
    require(entries.at("logs/20261021-101500-123-p42/startup.log").method == 8 &&
                feedback::zip(log, 0, 0).size() < repeated.size() / 5,
            "Repetitive logs were not deflated");
    require(entries.at("game/noise.bin").method == 0, "Incompressible data was not stored");
    require(entries.at("logs/empty.log").method == 0, "Empty file was not stored");
    require(entries.at("mods/中文.txt").flags == 0x0800 && entries.at("feedback.json").flags == 0,
            "UTF-8 name flag is wrong");
    require(read16(archive, 10) == 0x5000 && read16(archive, 12) == 0x5955,
            "DOS timestamp was not written");
    require(unzip(feedback::zip({}, 0, 0)).empty(), "Empty archive is invalid");
}

void zipNames() {
    for (const auto* name : {"feedback.json", "logs/a/runtime.log", "中文/日志.txt"})
        require(feedback::safeName(name), "Safe name was rejected");
    for (const auto* name : {"", "/abs", "a/", "../x", "a/../b", "a//b", "./a", "C:/x", "a\\b"})
        require(!feedback::safeName(name), "Unsafe name was accepted");
    require(!feedback::safeName(std::string("a\0b", 3)), "NUL name was accepted");
    const std::vector<feedback::File> unsafe = {{"../escape", bytes("x")}};
    rejects([&] { feedback::zip(unsafe, 0, 0); }, "Unsafe zip member was written");
}

void tails() {
    require(feedback::tail("short\n", 100) == "short\n", "Short file was changed");
    const auto kept = feedback::tail("line one\nline two\nline three\n", 15);
    require(kept == "[isaac-lan feedback: dropped 18 older bytes]\nline three\n",
            "Tail did not restart at a line boundary");
    const std::string wide = std::string(20, 'x') + "日志日志日志";
    const auto cut = feedback::tail(wide, 10);
    require(cut == "[isaac-lan feedback: dropped 29 older bytes]\n志日志",
            "Tail split a UTF-8 sequence");
    require(feedback::tail("partial\nnext\n", 100, 10) ==
                "[isaac-lan feedback: dropped 18 older bytes]\nnext\n",
            "Unread prefix was not counted or the partial line was kept");
}

void redaction() {
    const std::vector<std::string> profiles = {"C:\\Users\\Alice"};
    const auto redacted = feedback::redact(
        "a=C:\\Users\\Alice\\Documents b=c:/users/ALICE/x c=\"C:\\\\Users\\\\Alice\\\\y\" "
        "d=C:\\Users\\Alice2\\z e=C:\\Users\\Alice\n"
        "steam=D:/Steam/userdata/123456789/250900 keep=userdata/abc",
        profiles);
    require(redacted == "a=%USERPROFILE%\\Documents b=%USERPROFILE%/x "
                        "c=\"%USERPROFILE%\\\\y\" d=C:\\Users\\Alice2\\z e=%USERPROFILE%\n"
                        "steam=D:/Steam/userdata/<steamid>/250900 keep=userdata/abc",
            "Profile or Steam paths were not redacted exactly");
    const std::vector<std::string> tiny = {"C:\\"};
    require(feedback::redact("C:\\Games", tiny) == "C:\\Games", "Short profile was redacted");
}

void launchSelection() {
    const std::string current = "20261021-101500-123-p42";
    const auto selected = feedback::launches({"20261020-090000-001-p7", "20261019-080000-000-p3",
                                              current, "20261021-101500-123-p42-1", "notes",
                                              "20261020-090000-001-p7-2", "20261022-000000-000-p9"},
                                             current);
    require(selected == std::vector<std::string>{"20261020-090000-001-p7-2", current},
            "Wrong launches were selected");
    require(feedback::launches({}, current) == std::vector<std::string>{current},
            "Current launch alone was not selected");
    require(feedback::launches({"20261020-090000-001-p7"}, "").empty(),
            "Launches were selected without a current launch");
    require(!feedback::launchName("20261021-101500-123-p") &&
                !feedback::launchName("20261021-101500-123-p42-") &&
                !feedback::launchName("2026102a-101500-123-p42"),
            "Malformed launch names were accepted");
}

void validation() {
    require(feedback::validDescription("进入 Boss 房后客机卡住"), "Description was rejected");
    for (const auto& text :
         {std::string(), std::string(" \t\n"), std::string(4097, 'x'), std::string("a\x01")})
        require(!feedback::validDescription(text), "Invalid description was accepted");
    require(feedback::validDescription(std::string(4096, 'x')), "Maximum description rejected");
    require(feedback::validEndpoint(feedback::defaultEndpoint), "Default endpoint rejected");
    require(feedback::validEndpoint("http://127.0.0.1:27180/isaac-lan/feedback/v1/submit"),
            "Loopback endpoint rejected");
    for (const auto* endpoint : {"http://example.com/submit", "https://", "https://host",
                                 "ftp://host/x", "https://host/a b", "https://host/\"x"})
        require(!feedback::validEndpoint(endpoint), "Invalid endpoint was accepted");
    std::array<std::uint8_t, 16> random{};
    random.fill(0xff);
    const auto id = feedback::uuid(random);
    require(id == "ffffffff-ffff-4fff-bfff-ffffffffffff" && feedback::validUuid(id),
            "UUID version bits are wrong");
    require(!feedback::validUuid("FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF"),
            "Uppercase UUID was accepted");
    require(feedback::validId("261021-K7Q3"), "Feedback id was rejected");
    for (const auto* text : {"261021-K7QI", "261021-k7q3", "26102-K7Q3X", "261021-K7Q"})
        require(!feedback::validId(text), "Malformed feedback id was accepted");
    require(feedback::printable("ok\xff\n名") == "ok? 名", "Printable conversion is wrong");
}

void json() {
    const feedback::Manifest value{"他说 \"卡住了\"\n然后\\退出",
                                   "2026-10-21T10:15:00+08:00",
                                   "isaac-lan/0.4.2",
                                   "1.9.7.17.J460",
                                   {{"phase", "running"}},
                                   {"EID", "Mod \"x\""},
                                   {"logs/a.log"}};
    const auto text = feedback::manifest(value);
    require(text.starts_with("{\"schema\":1,"), "Manifest schema is missing");
    require(feedback::jsonField(text, "description") == value.description,
            "Description did not round trip");
    require(feedback::jsonField(text, "phase") == std::optional<std::string>("running"),
            "Context was not encoded");
    require(text.find("\"mods\":[\"EID\",\"Mod \\\"x\\\"\"]") != std::string::npos,
            "Mods were not encoded");
    require(feedback::jsonString(std::string("\x01\x7f", 2)) == "\"\\u0001\\u007f\"",
            "Control characters were not escaped");
    require(feedback::jsonField(R"({"message": "\u7ef4\u62a4\ud83d\ude00"})", "message") ==
                std::optional<std::string>("维护😀"),
            "Unicode escapes did not decode");
    for (const auto* body :
         {R"({"id": 7})", R"({"id": "\ud83d"})", R"({"id": "\x"})", R"({"id": "open)", "{}"})
        require(!feedback::jsonField(body, "id"), "Invalid JSON string was accepted");
}

void outcomes() {
    auto result = feedback::interpret(201, R"({"id": "261021-K7Q3", "duplicate": false})");
    require(result.accepted && result.id == "261021-K7Q3" && !result.retry &&
                result.text.find("261021-K7Q3") != std::string::npos,
            "Accepted upload was not reported");
    require(feedback::interpret(200, R"({"id": "261021-K7Q3", "duplicate": true})").accepted,
            "Duplicate upload was not accepted");
    require(!feedback::interpret(201, R"({"id": "../x"})").accepted, "Malformed id was accepted");
    result = feedback::interpret(503, R"({"error": "paused", "message": "维护中"})");
    require(!result.accepted && !result.retry && result.text == "维护中",
            "Pause message was not shown");
    require(feedback::interpret(503, R"({"error": "paused"})").text.find("暂时关闭") !=
                std::string::npos,
            "Pause without message has no text");
    for (const auto status : {400, 413, 429, 404})
        require(!feedback::interpret(status, "<html>").retry, "Rejected upload was retried");
    require(!feedback::interpret(503, R"({"error": "busy"})").retry, "Busy server was retried");
    require(feedback::interpret(0, "").retry && feedback::interpret(502, "<html>").retry,
            "Transient failure was not retried");
}
} // namespace

int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"zip-layout", zipLayout},
                     {"zip-names", zipNames},
                     {"tails", tails},
                     {"redaction", redaction},
                     {"launch-selection", launchSelection},
                     {"validation", validation},
                     {"json", json},
                     {"outcomes", outcomes}});
}

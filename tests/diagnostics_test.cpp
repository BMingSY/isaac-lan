#include "app/configuration.h"
#include "core/performance.h"
#include "diagnostics/input_latency.h"
#include "test_support.h"
#include <chrono>
#include <filesystem>
#include <fstream>
#include <limits>

namespace {
void defaults() {
    const auto parsed = isaac::configuration::parse(isaac::configuration::defaults);
    require(parsed.warnings.empty(), "Default configuration is invalid");
    require(parsed.settings.inputHz == 60, "Default guest input rate changed");
    require(parsed.settings.udp, "UDP is not the default transport");
    require(parsed.settings.chat.backgroundImage.empty() && parsed.settings.chat.opacity == 70,
            "Default chat background is not a translucent solid color");
    require(isaac::configuration::missingDefaults(parsed).empty(),
            "Complete config needs migration");
    require(parsed.settings.logLevel == isaac::logging::Level::info &&
                !parsed.settings.performance && parsed.settings.sampleIntervalMs == 1000,
            "Release defaults enable detailed diagnostics");
}
void validation() {
    using isaac::configuration::parse;
    require(!parse("[network]\ntransport=tcp").settings.udp &&
                parse("[network]\ntransport=udp").settings.udp &&
                parse("[network]\ntransport=unknown").warnings.size() == 1,
            "Transport selection or invalid-value fallback changed");
    const auto chat =
        parse("[chat]\nbackground_opacity=45\nbackground_color=Ab3400\n"
              "border_color=123456\ntext_color=FFFFFF\nbackground_image=背景/my panel.png\n");
    require(chat.warnings.empty() && chat.settings.chat.opacity == 45 &&
                chat.settings.chat.background == 0xab3400 &&
                chat.settings.chat.border == 0x123456 && chat.settings.chat.text == 0xffffff &&
                chat.settings.chat.backgroundImage == "背景/my panel.png",
            "Custom chat appearance was not preserved");
    require(
        parse("[chat]\nbackground_image=\"C:\\My UI\\背景.png\"").settings.chat.backgroundImage ==
            "C:\\My UI\\背景.png",
        "Quoted absolute image path was not preserved");
    for (const auto opacity : {0u, 100u})
        require(
            parse("[chat]\nbackground_opacity=" + std::to_string(opacity)).settings.chat.opacity ==
                opacity,
            "Chat opacity endpoint was rejected");
    const auto badChat = parse("[chat]\nbackground_opacity=101\nbackground_color=#ffffff\n"
                               "border_color=bad\ntext_color=gggggg\n");
    require(badChat.warnings.size() == 4 && badChat.settings.chat.opacity == 70 &&
                badChat.settings.chat.background == 0x231b18 &&
                badChat.settings.chat.text == 0xe8dfcb,
            "Malformed chat style bypassed readable defaults");
    for (const auto hz : {30u, 60u}) {
        const auto input = parse("[network]\ninput_hz=" + std::to_string(hz));
        require(input.warnings.empty() && input.settings.inputHz == hz,
                "Supported guest input rate was rejected");
    }
    for (const auto value : {"0", "59", "120", "-30", "30.0", "60oops", ""}) {
        const auto invalid = parse("[network]\ninput_hz=" + std::string(value));
        require(invalid.settings.inputHz == 60 && invalid.warnings.size() == 1,
                "Invalid guest input rate bypassed defaults");
    }
    const auto duplicate = parse("[network]\ninput_hz=30\ninput_hz=60\n");
    require(duplicate.settings.inputHz == 30 && duplicate.warnings.size() == 1,
            "Repeated input setting replaced the first value");
    const auto valid = parse("\xef\xbb\xbf[logging]\r\nlevel = DEBUG\r\n"
                             "[diagnostics]\nperformance = true\nsample_interval_ms = 250\n");
    require(valid.warnings.empty() && valid.settings.performance &&
                valid.settings.logLevel == isaac::logging::Level::debug &&
                valid.settings.sampleIntervalMs == 250,
            "Valid BOM/CRLF configuration was rejected");
    for (const auto value : {"0", "99", "60001", "-1", "999999999999", "250oops"}) {
        const auto invalid = parse("[diagnostics]\nsample_interval_ms=" + std::string(value));
        require(invalid.settings.sampleIntervalMs == 1000 && invalid.warnings.size() == 1,
                "Invalid interval bypassed defaults");
    }
    const auto invalid = parse("[logging]\nlevel=broken\nlevel=DEBUG\n"
                               "[diagnostics]\nperformance=TRUE\nunknown=true\nbroken\n");
    require(invalid.warnings.size() == 5 && !invalid.settings.performance &&
                invalid.settings.logLevel == isaac::logging::Level::info,
            "Unknown, duplicate or invalid values were silently accepted");
}
void preservation() {
    const auto root = std::filesystem::temp_directory_path() /
                      ("isaac-lan-config-regression-" +
                       std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    require(std::filesystem::create_directory(root), "Temporary directory is already in use");
    const auto path = root / "config.ini";
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::filesystem::remove_all(path);
        }
    } cleanup{root};
    require(isaac::configuration::load(path).warnings.empty(), "Default file was not created");
    const std::string custom = "\xef\xbb\xbf[logging]\r\nlevel = ERROR\r\n; keep my comments\r\n"
                               "[custom]\r\nfuture_setting=yes";
    {
        std::ofstream file(path, std::ios::binary);
        file << custom;
    }
    require(isaac::configuration::load(path).settings.logLevel == isaac::logging::Level::error,
            "User configuration did not override defaults");
    require(isaac::configuration::load(path).settings.inputHz == 60,
            "An older configuration did not use the default input rate");
    std::ifstream file(path, std::ios::binary);
    const std::string upgraded(std::istreambuf_iterator<char>(file), {});
    require(upgraded.starts_with(custom) && upgraded.find("input_hz = 60") != std::string::npos,
            "Migration replaced user values/comments or omitted new defaults");
    const auto parsed = isaac::configuration::parse(upgraded);
    require(isaac::configuration::missingDefaults(parsed).empty() && parsed.warnings.size() == 1,
            "Migration lost a known key or duplicated an existing setting");
    file.close();
    isaac::configuration::load(path);
    file.open(path, std::ios::binary);
    require(std::string(std::istreambuf_iterator<char>(file), {}) == upgraded,
            "Repeated startup duplicated settings or comments");
    file.close();
    {
        std::ofstream file(path, std::ios::binary);
        file << "[network]\ninput_hz=120\ninput_hz=30\n; do not repair my text\n";
    }
    const auto invalid = isaac::configuration::load(path);
    require(invalid.settings.inputHz == 60 && invalid.warnings.size() == 2,
            "Migration silently repaired an invalid or duplicate value");
    file.open(path, std::ios::binary);
    const std::string retained(std::istreambuf_iterator<char>(file), {});
    require(retained.find("input_hz=120\ninput_hz=30\n; do not repair my text") !=
                    std::string::npos &&
                retained.find("input_hz = 60") == std::string::npos,
            "Migration rewrote an existing input setting");
    file.close();
    const std::string nearLimit = "[logging]\nlevel=ERROR\n;" + std::string(65500, 'a');
    {
        std::ofstream file(path, std::ios::binary);
        file << nearLimit;
    }
    const auto unwritten = isaac::configuration::load(path);
    require(unwritten.settings.logLevel == isaac::logging::Level::error &&
                unwritten.settings.inputHz == 60 && unwritten.warnings.size() == 1,
            "Failed migration discarded runtime settings or failed to report itself");
    file.open(path, std::ios::binary);
    require(std::string(std::istreambuf_iterator<char>(file), {}) == nearLimit,
            "Failed migration changed the original file");
    file.close();
    {
        std::ofstream oversized(path, std::ios::binary);
        oversized << std::string(65537, 'a');
    }
    require(isaac::configuration::load(path).warnings.size() == 1,
            "Oversized configuration was read without a bound");
}
void metrics() {
    using Clock = std::chrono::steady_clock;
    using namespace std::chrono_literals;
    isaac::diagnostics::InputLatency latency;
    const auto start = Clock::time_point{};
    latency.capture(1, start);
    require(latency.present(1, start + 8ms) == 8 && !latency.present(1, start + 16ms),
            "Presentation latency duplicated one input sample");
    require(latency.confirm(1, start + 90ms) == 90 && !latency.confirm(1, start + 100ms),
            "Repeated state acknowledgement duplicated latency");
    latency.capture(129, start + 1s);
    require(!latency.present(1, start + 1s) && !latency.confirm(2, start + 1s),
            "Evicted sample was mistaken for a newer input");
    latency = {};
    latency.capture(0, start);
    require(latency.confirm(0, start + 40ms) == 40,
            "New session retained old input sequence metrics");
    isaac::diagnostics::Window window;
    for (unsigned i = 1; i <= 100; ++i)
        window.add(i);
    require(window.percentile(50) == 50 && window.percentile(95) == 95 &&
                window.percentile(99) == 99 && window.maximum == 100,
            "Percentiles hide a latency spike");
    const auto size = sizeof(window);
    for (unsigned i = 0; i < 100000; ++i)
        window.add(2);
    require(sizeof(window) == size && window.count == 100100 && window.percentile(99) == 2,
            "Long diagnostics accumulated samples or kept stale percentiles");
    window.add(-1);
    window.add(std::numeric_limits<double>::infinity());
    window.add(std::numeric_limits<double>::quiet_NaN());
    require(window.count == 100100, "Malformed metrics poisoned the window");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"defaults", defaults},
                     {"validation", validation},
                     {"preservation", preservation},
                     {"bounded-metrics", metrics}});
}

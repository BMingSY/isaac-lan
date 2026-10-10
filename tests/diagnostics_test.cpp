#include "app/configuration.h"
#include "core/performance.h"
#include "test_support.h"
#include <chrono>
#include <filesystem>
#include <fstream>
#include <limits>

namespace {
void defaults() {
    const auto parsed = isaac::configuration::parse(isaac::configuration::defaults);
    require(parsed.warnings.empty(), "Default configuration is invalid");
    require(parsed.settings.logLevel == isaac::logging::Level::info &&
                !parsed.settings.performance && parsed.settings.sampleIntervalMs == 1000,
            "Release defaults enable detailed diagnostics");
}
void validation() {
    using isaac::configuration::parse;
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
    const std::string custom = "[logging]\nlevel=ERROR\n; keep my comments\n";
    {
        std::ofstream file(path, std::ios::binary);
        file << custom;
    }
    require(isaac::configuration::load(path).settings.logLevel == isaac::logging::Level::error,
            "User configuration did not override defaults");
    std::ifstream file(path, std::ios::binary);
    require(std::string(std::istreambuf_iterator<char>(file), {}) == custom,
            "Loading replaced the user configuration");
    file.close();
    {
        std::ofstream oversized(path, std::ios::binary);
        oversized << std::string(65537, 'a');
    }
    require(isaac::configuration::load(path).warnings.size() == 1,
            "Oversized configuration was read without a bound");
}
void metrics() {
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

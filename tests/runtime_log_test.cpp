#include "diagnostics/runtime_log.h"
#include "diagnostics/performance.h"
#include "test_support.h"
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <regex>

namespace {
std::string read(const std::filesystem::path& file) {
    std::ifstream stream(file, std::ios::binary);
    return {std::istreambuf_iterator<char>(stream), {}};
}
void pathAndRecords() {
    wchar_t temporary[MAX_PATH]{};
    require(GetTempPathW(MAX_PATH, temporary) != 0, "Temporary directory unavailable");
    const auto root = std::filesystem::path(temporary) /
                      (L"isaac-lan-log-test-" + std::to_wstring(GetCurrentProcessId()));
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::error_code error;
            std::filesystem::remove_all(path, error);
        }
    } cleanup{root};
    using namespace isaac::logging;
    const auto fallback = root / L"默认文档";
    require(initialize(fallback), "Could not initialize profile log directory");
    write("bootstrap=PASS");
    // Native game paths can mix '/' and '\\' unlike the fallback path.
    nativeFileOpened((fallback / L"log.txt").generic_wstring().c_str());
    write("network_failure=example\nnext line");
    const auto fallbackLaunch = directory();
    const auto initial = read(fallbackLaunch / L"startup.log");
    const std::regex lines(
        R"(\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}[+-][0-9]{2}:[0-9]{2}\] \[(INFO|ERROR)\] \[pid=[0-9]+\] [^\r\n]*\r\n)");
    std::size_t consumed = 0;
    unsigned count = 0;
    for (std::sregex_iterator i(initial.begin(), initial.end(), lines), end; i != end; ++i) {
        require(static_cast<std::size_t>(i->position()) == consumed,
                "Log contains an unformatted or multiline record");
        consumed += i->length();
        ++count;
    }
    require(count == 3 && consumed == initial.size(), "Bootstrap was duplicated or a record lost");
    require(initial.find("[ERROR]") != initial.npos &&
                initial.find("example\\nnext line") != initial.npos,
            "Native log lost error severity or escaped text");
    const auto custom = root / L"独立存档";
    nativeFileOpened((custom / L"options.ini").c_str());
    write("same_destination=PASS");
    require(!std::filesystem::exists(custom), "A non-log native file redirected output");
    nativeFileOpened((custom / L"LOG.TXT").c_str());
    write("custom_destination=PASS");
    require(read(directory() / L"startup.log").find("custom_destination=PASS") != std::string::npos,
            "Custom native log path was not followed");
    require(read(fallbackLaunch / L"startup.log").find("custom_destination=PASS") ==
                std::string::npos,
            "Log continued writing to the previous profile");
    const auto launch = directory();
    write("state_cost filtered_debug");
    require(read(launch / L"startup.log").find("filtered_debug") == std::string::npos,
            "Release wrote DEBUG logs");
    require(!beginRun("../bad", "host", false), "Seed escaped the launch directory");
    require(beginRun("LBCD 0G4M", "host", false), "Run log was not created");
    const auto first = directory();
    write("first_game=PASS");
    endRun();
    require(beginRun("LBCD 0G4M", "client", true), "Same-seed continuation lost its log");
    const auto second = directory();
    require(first != second, "Same seed overwrote an earlier game");
    write("second_game=PASS");
    endRun();
    require(read(first / L"runtime.log").find("first_game=PASS") != std::string::npos &&
                read(first / L"runtime.log").find("second_game=PASS") == std::string::npos &&
                read(second / L"runtime.log").find("continued=true") != std::string::npos,
            "Separate run logs mixed or lost historical evidence");
    configure(Level::debug);
    write("state_cost explicit_debug");
    require(read(launch / L"startup.log").find("explicit_debug") != std::string::npos,
            "Diagnostic override did not enable DEBUG logs");
    const auto blocked = root / L"blocked";
    const auto destination = blocked / L"isaac-lan/logs" / launch.filename();
    std::filesystem::create_directories(destination);
    const auto held =
        CreateFileW((destination / L"startup.log").c_str(), GENERIC_READ | GENERIC_WRITE,
                    FILE_SHARE_READ, nullptr, CREATE_ALWAYS, 0, nullptr);
    require(held != INVALID_HANDLE_VALUE, "Could not hold the existing log");
    require(!initialize(blocked), "An exclusive file lock did not reject log selection");
    write("failed_reopen_preserved=PASS");
    CloseHandle(held);
    require(read(launch / L"startup.log").find("failed_reopen_preserved=PASS") != std::string::npos,
            "An unsuccessful log selection closed the existing output");
    shutdown();
}
void metricsLifecycle() {
    const auto root = std::filesystem::temp_directory_path() /
                      ("isaac-lan-metrics-test-" + std::to_string(GetCurrentProcessId()));
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            isaac::logging::shutdown();
            std::error_code ec;
            std::filesystem::remove_all(path, ec);
        }
    } cleanup{root};
    require(isaac::logging::initialize(root), "Could not initialize metric test logs");
    isaac::diagnostics::configure({});
    require(isaac::logging::beginRun("YV039KQF", "client", false), "Could not start disabled run");
    isaac::diagnostics::beginRun();
    isaac::diagnostics::sample("apply", 2);
    isaac::diagnostics::render();
    isaac::diagnostics::endRun();
    require(!std::filesystem::exists(isaac::logging::directory() / "performance.jsonl"),
            "Disabled metrics wrote a file");
    isaac::logging::endRun();
    isaac::configuration::Settings settings;
    settings.performance = true;
    isaac::diagnostics::configure(settings);
    DWORD baseline = 0, after = 0;
    GetProcessHandleCount(GetCurrentProcess(), &baseline);
    for (unsigned run = 0; run < 40; ++run) {
        require(isaac::logging::beginRun("YV039KQF", "client", false),
                "Could not start metric run");
        isaac::diagnostics::beginRun();
        for (unsigned sample = 0; sample < 10000; ++sample)
            isaac::diagnostics::sample("apply", 2);
        isaac::diagnostics::sample("bad\"name", 1);
        isaac::diagnostics::counter("entities", 32);
        isaac::diagnostics::endRun();
        const auto text = read(isaac::logging::directory() / "performance.jsonl");
        require(text.find("\"count\":10000") != text.npos &&
                    text.find("\"percentile_samples\":512") != text.npos,
                "Metric samples are missing or unbounded");
        require(text.find("\"entities\":32") != text.npos && text.find("bad") == text.npos,
                "Metrics lost counters or accepted an unsafe name");
        isaac::logging::endRun();
    }
    GetProcessHandleCount(GetCurrentProcess(), &after);
    require(after <= baseline, "Repeated metric sessions leaked file handles");
    std::printf("RESOURCE metric_runs=40 handles_before=%lu handles_after=%lu\n", baseline, after);
}
} // namespace
int main(int argc, char** argv) {
    return runTests(
        argc, argv,
        {{"path-and-records", pathAndRecords}, {"metrics-lifecycle", metricsLifecycle}});
}

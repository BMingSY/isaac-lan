#include "diagnostics/runtime_log.h"
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
    const auto initial = read(fallback / L"isaac-lan/probe.log");
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
    require(read(custom / L"isaac-lan/probe.log").find("custom_destination=PASS") !=
                std::string::npos,
            "Custom native log path was not followed");
    require(read(fallback / L"isaac-lan/probe.log").find("custom_destination=PASS") ==
                std::string::npos,
            "Log continued writing to the previous profile");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"path-and-records", pathAndRecords}});
}

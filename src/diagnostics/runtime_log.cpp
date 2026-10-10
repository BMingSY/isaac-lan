#include "diagnostics/runtime_log.h"
#include <windows.h>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <mutex>
#include <system_error>

namespace isaac::logging {
namespace {
std::recursive_mutex mutex;
std::filesystem::path launchDirectory, output;
std::wstring launchName;
std::string startup;
bool confirmed = false;
unsigned run = 0;
HANDLE file = INVALID_HANDLE_VALUE;
std::atomic<Level> minimum{Level::info};
void closeFile() {
    if (file != INVALID_HANDLE_VALUE) {
        CloseHandle(file);
        file = INVALID_HANDLE_VALUE;
    }
}
bool select(const std::filesystem::path& path) {
    const auto next =
        CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                    OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (next == INVALID_HANDLE_VALUE)
        return false;
    closeFile();
    file = next;
    output = path;
    return true;
}
bool append(std::string_view bytes) {
    if (file == INVALID_HANDLE_VALUE)
        return false;
    DWORD written = 0;
    return WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) &&
           written == bytes.size();
}
std::wstring uniqueName() {
    SYSTEMTIME time{};
    GetLocalTime(&time);
    wchar_t name[96];
    std::swprintf(name, 96, L"%04u%02u%02u-%02u%02u%02u-%03u-p%lu", time.wYear, time.wMonth,
                  time.wDay, time.wHour, time.wMinute, time.wSecond, time.wMilliseconds,
                  GetCurrentProcessId());
    return name;
}
} // namespace
void configure(Level value) {
    minimum.store(value);
}
bool enabled(Level severity) {
    return severity >= minimum.load();
}
bool initialize(const std::filesystem::path& gameLogDirectory) {
    std::lock_guard lock(mutex);
    const auto logs = gameLogDirectory / L"isaac-lan/logs";
    std::error_code error;
    std::filesystem::create_directories(logs, error);
    if (error)
        return false;
    if (launchName.empty()) {
        const auto name = uniqueName();
        for (unsigned suffix = 0; suffix < 1000; ++suffix) {
            launchName = name + (suffix ? L"-" + std::to_wstring(suffix) : L"");
            if (std::filesystem::create_directory(logs / launchName, error))
                break;
            if (error || suffix == 999) {
                launchName.clear();
                return false;
            }
        }
    } else {
        std::filesystem::create_directories(logs / launchName, error);
        if (error)
            return false;
    }
    const auto next = logs / launchName;
    if (!select(next / L"startup.log"))
        return false;
    launchDirectory = next;
    return true;
}
std::filesystem::path directory() {
    std::lock_guard lock(mutex);
    return output.parent_path();
}
bool beginRun(const std::string& seed, const std::string& role, bool continued) {
    std::lock_guard lock(mutex);
    std::string clean;
    for (const auto c : seed)
        if ((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
            clean += c;
    if (clean.size() != 8 || (role != "host" && role != "client" && role != "solo"))
        return false;
    char name[64];
    std::snprintf(name, sizeof(name), "%03u-%s-%s", ++run, clean.c_str(), role.c_str());
    const auto path = launchDirectory / name;
    std::error_code error;
    if (!std::filesystem::create_directory(path, error) || error)
        return false;
    if (!select(path / L"runtime.log"))
        return false;
    write("run_begin seed=" + clean + " role=" + role +
          " continued=" + (continued ? "true" : "false"));
    return true;
}
void endRun() {
    std::lock_guard lock(mutex);
    write("run_end");
    if (!launchDirectory.empty())
        select(launchDirectory / L"startup.log");
}
void shutdown() {
    std::lock_guard lock(mutex);
    closeFile();
}
void nativeFileOpened(const wchar_t* name) {
    const std::filesystem::path path(name);
    if (_wcsicmp(path.filename().c_str(), L"log.txt"))
        return;
    std::lock_guard lock(mutex);
    std::error_code error;
    const auto actual = std::filesystem::absolute(path, error).lexically_normal().parent_path();
    if (error)
        return;
    const auto destination = actual / L"isaac-lan/logs" / launchName;
    if (destination != launchDirectory && !initialize(actual))
        return;
    if (!confirmed) {
        if (destination != output.parent_path())
            return;
        // Only bootstrap can precede the original log open. Preserve its
        // evidence at a custom save path, without duplicating the fallback.
        if (!startup.empty()) {
            std::ifstream existing(output, std::ios::binary);
            if (existing.peek() == std::ifstream::traits_type::eof())
                append(startup);
        }
        startup.clear();
        confirmed = true;
        const auto encoded = actual.u8string();
        write("game_log_directory=" + std::string(encoded.begin(), encoded.end()) +
              " source=native");
    }
}
void write(const std::string& message) {
    const auto severity = level(message);
    if (!enabled(severity))
        return;
    std::lock_guard lock(mutex);
    SYSTEMTIME time{};
    GetLocalTime(&time);
    TIME_ZONE_INFORMATION zone{};
    const auto daylight = GetTimeZoneInformation(&zone);
    const auto bias =
        zone.Bias + (daylight == TIME_ZONE_ID_DAYLIGHT ? zone.DaylightBias : zone.StandardBias);
    const int minutes = -bias, absolute = minutes < 0 ? -minutes : minutes;
    char timestamp[64];
    std::snprintf(timestamp, sizeof(timestamp), "%04u-%02u-%02u %02u:%02u:%02u.%03u%c%02d:%02d",
                  time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
                  time.wMilliseconds, minutes < 0 ? '-' : '+', absolute / 60, absolute % 60);
    const auto bytes = record(timestamp, GetCurrentProcessId(), severity, message);
    if (!confirmed && startup.size() + bytes.size() <= 256 * 1024)
        startup += bytes;
    append(bytes);
    if (severity == Level::error && file != INVALID_HANDLE_VALUE)
        FlushFileBuffers(file);
}
} // namespace isaac::logging

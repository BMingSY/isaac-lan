#include "runtime_log.h"
#include "log_record.h"
#include <windows.h>
#include <cstdio>
#include <mutex>
#include <system_error>

namespace isaac::logging {
namespace {
std::recursive_mutex mutex;
std::filesystem::path output;
std::string startup;
bool confirmed = false;
bool append(std::string_view bytes) {
    HANDLE file = CreateFileW(output.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                              nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return false;
    DWORD written = 0;
    const bool success =
        WriteFile(file, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr) &&
        written == bytes.size();
    CloseHandle(file);
    return success;
}
} // namespace
bool initialize(const std::filesystem::path& gameLogDirectory) {
    std::lock_guard lock(mutex);
    const auto directory = gameLogDirectory / L"isaac-lan";
    std::error_code error;
    std::filesystem::create_directories(directory, error);
    if (error)
        return false;
    output = directory / L"probe.log";
    return true;
}
void nativeFileOpened(const wchar_t* name) {
    const std::filesystem::path path(name);
    if (_wcsicmp(path.filename().c_str(), L"log.txt"))
        return;
    std::lock_guard lock(mutex);
    // Resolve relative/native extended paths exactly where the game opened
    // its own log; configurable save paths and isolated profiles follow it.
    std::error_code error;
    const auto directory = std::filesystem::absolute(path, error).lexically_normal().parent_path();
    const auto previous = output;
    if (error || !initialize(directory))
        return;
    if (!confirmed) {
        // The fallback usually already is the game's actual directory.
        // Replaying it there would duplicate every bootstrap record.
        std::error_code sameError;
        if (!std::filesystem::equivalent(previous, output, sameError))
            append(startup);
        startup.clear();
        confirmed = true;
        const auto encoded = directory.u8string();
        write("game_log_directory=" + std::string(encoded.begin(), encoded.end()) +
              " source=native");
    }
}
void write(const std::string& message) {
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
    const auto bytes = record(timestamp, GetCurrentProcessId(), level(message), message);
    // Keep bootstrap diagnostics available if the game fails before opening
    // log.txt. Replay those few lines if its actual path differs from fallback.
    if (!confirmed && startup.size() < 256 * 1024)
        startup += bytes;
    append(bytes);
}
} // namespace isaac::logging

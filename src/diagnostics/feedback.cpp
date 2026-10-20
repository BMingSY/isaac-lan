#include "diagnostics/feedback.h"
#include "core/feedback.h"
#include "core/chat.h"
#include "diagnostics/runtime_log.h"
#include "engine/lua_api.h"
#include <bcrypt.h>
#include <shlobj.h>
#include <winhttp.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <system_error>
#include <thread>
#include <tuple>
#include <utility>

#ifndef WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY
#define WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY 4
#endif

namespace isaac::feedback {
namespace {
using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;
constexpr auto cooldown = 30s;
// Only transient failures repeat, with the same submission key.
constexpr std::array<std::chrono::seconds, 3> attempts{0s, 5s, 20s};
constexpr std::size_t maxMods = 200, maxContext = 32, maxFieldBytes = 200, maxFiles = 200;
constexpr std::size_t maxResponseBytes = 4096, readChunk = 1024 * 1024;
// Room for the manifest and zip headers under the receiver's limit.
constexpr std::size_t archiveHeadroom = 64 * 1024;
constexpr int resolveMs = 10000, connectMs = 10000, sendMs = 60000, receiveMs = 30000;

lua::API lua;
Environment environment;

struct Shared {
    std::mutex mutex;
    bool busy = false;
    std::optional<std::pair<bool, std::string>> result;
    std::optional<Clock::time_point> started;
};
Shared& shared() {
    // Never destroyed: a detached upload may still finish during process exit.
    static auto* value = new Shared;
    return *value;
}

struct Job {
    std::string description, mods, context;
    std::filesystem::path launch;
    Environment environment;
};
struct Package {
    std::vector<std::uint8_t> archive;
    std::string stamp;
};
struct Internet {
    HINTERNET value = nullptr;
    ~Internet() {
        if (value)
            WinHttpCloseHandle(value);
    }
};
struct Handle {
    HANDLE value = INVALID_HANDLE_VALUE;
    ~Handle() {
        if (value != INVALID_HANDLE_VALUE)
            CloseHandle(value);
    }
};

std::wstring wide(std::string_view text) {
    if (text.empty())
        return {};
    const auto size =
        MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
    std::wstring result(static_cast<std::size_t>(std::max(size, 0)), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(),
                        size);
    return result;
}
std::string utf8(const std::filesystem::path& path) {
    const auto text = path.u8string();
    return {text.begin(), text.end()};
}
std::string generic(const std::filesystem::path& path) {
    const auto text = path.generic_u8string();
    return {text.begin(), text.end()};
}
std::string trim(std::string_view text) {
    const auto begin = text.find_first_not_of(" \t\r\n");
    if (begin == text.npos)
        return {};
    return std::string(text.substr(begin, text.find_last_not_of(" \t\r\n") - begin + 1));
}
std::vector<std::string> lines(std::string_view text, std::size_t limit) {
    std::vector<std::string> result;
    while (!text.empty() && result.size() < limit) {
        const auto end = text.find('\n');
        auto line = printable(trim(text.substr(0, end)));
        if (!line.empty())
            result.emplace_back(chat::boundedOutput(line, maxFieldBytes));
        text = end == text.npos ? std::string_view{} : text.substr(end + 1);
    }
    return result;
}
std::array<std::uint8_t, 16> random16() {
    std::array<std::uint8_t, 16> bytes{};
    if (BCryptGenRandom(nullptr, bytes.data(), static_cast<ULONG>(bytes.size()),
                        BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
        throw std::runtime_error("random");
    return bytes;
}
std::vector<std::string> profiles() {
    wchar_t path[MAX_PATH]{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_PROFILE, nullptr, SHGFP_TYPE_CURRENT, path)))
        return {};
    std::vector<std::string> result{utf8(std::filesystem::path(path))};
    // Temporary and legacy paths may spell the profile as 8.3, e.g. ADMINI~1.
    wchar_t brief[MAX_PATH]{};
    const auto length = GetShortPathNameW(path, brief, MAX_PATH);
    if (length && length < MAX_PATH && std::wstring_view(brief) != path)
        result.push_back(utf8(std::filesystem::path(brief)));
    return result;
}
std::optional<std::string> readTail(const std::filesystem::path& path, std::size_t limit,
                                    std::size_t& omitted) {
    // Logs stay open for appending in this and the game's process.
    Handle file{CreateFileW(path.c_str(), GENERIC_READ,
                            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr)};
    LARGE_INTEGER size{};
    if (file.value == INVALID_HANDLE_VALUE || !GetFileSizeEx(file.value, &size) ||
        size.QuadPart < 0)
        return {};
    const auto total = static_cast<std::uint64_t>(size.QuadPart);
    const auto keep = static_cast<std::size_t>(std::min<std::uint64_t>(total, limit));
    omitted = static_cast<std::size_t>(total - keep);
    LARGE_INTEGER offset{};
    offset.QuadPart = static_cast<LONGLONG>(omitted);
    if (!SetFilePointerEx(file.value, offset, nullptr, FILE_BEGIN))
        return {};
    std::string text(keep, '\0');
    std::size_t at = 0;
    DWORD read = 0;
    while (at < text.size() &&
           ReadFile(file.value, text.data() + at,
                    static_cast<DWORD>(std::min(readChunk, text.size() - at)), &read, nullptr) &&
           read)
        at += read;
    text.resize(at);
    return text;
}
void addText(std::vector<feedback::File>& files, std::string name,
             const std::filesystem::path& path, std::size_t limit,
             const std::vector<std::string>& redacted) {
    std::size_t omitted = 0;
    if (files.size() >= maxFiles || !safeName(name))
        return;
    if (const auto text = readTail(path, limit, omitted)) {
        const auto content = redact(tail(*text, limit, omitted), redacted);
        files.push_back({std::move(name), {content.begin(), content.end()}});
    }
}
std::vector<feedback::File> collect(const Job& job, std::size_t limit,
                                    const std::vector<std::string>& redacted) {
    namespace fs = std::filesystem;
    const auto logs = job.launch.parent_path();
    std::vector<std::string> names;
    std::error_code error;
    for (fs::directory_iterator it(logs, error), end; !error && it != end; it.increment(error))
        if (it->is_directory(error))
            names.push_back(utf8(it->path().filename()));
    std::vector<feedback::File> files;
    for (const auto& launch : launches(names, utf8(job.launch.filename()))) {
        const auto root = logs / wide(launch);
        std::vector<fs::path> paths;
        error.clear();
        for (fs::recursive_directory_iterator it(root, error), end; !error && it != end;
             it.increment(error)) {
            // launch/startup.log and launch/<run>/{runtime.log, performance.jsonl};
            // nothing else the player may have put there.
            const auto extension = it->path().extension();
            if (it.depth() > 1)
                it.disable_recursion_pending();
            else if (it->is_regular_file(error) && (extension == L".log" || extension == L".jsonl"))
                paths.push_back(it->path());
        }
        std::sort(paths.begin(), paths.end());
        for (const auto& path : paths)
            addText(files, "logs/" + launch + "/" + generic(path.lexically_relative(root)), path,
                    limit, redacted);
    }
    addText(files, "game/log.txt", logs.parent_path().parent_path() / L"log.txt", limit, redacted);
    addText(files, "config/config.ini", job.environment.config, limit, redacted);
    return files;
}
Package package(const Job& job) {
    SYSTEMTIME time{};
    GetLocalTime(&time);
    TIME_ZONE_INFORMATION zone{};
    const auto daylight = GetTimeZoneInformation(&zone);
    const auto bias =
        zone.Bias + (daylight == TIME_ZONE_ID_DAYLIGHT ? zone.DaylightBias : zone.StandardBias);
    const int minutes = -bias, absolute = minutes < 0 ? -minutes : minutes;
    char created[40], stamp[24];
    std::snprintf(created, sizeof(created), "%04u-%02u-%02uT%02u:%02u:%02u%c%02d:%02d", time.wYear,
                  time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
                  minutes < 0 ? '-' : '+', absolute / 60, absolute % 60);
    std::snprintf(stamp, sizeof(stamp), "%04u%02u%02u-%02u%02u%02u", time.wYear, time.wMonth,
                  time.wDay, time.wHour, time.wMinute, time.wSecond);
    const auto dosTime =
        static_cast<std::uint16_t>(time.wHour << 11 | time.wMinute << 5 | time.wSecond / 2);
    const auto dosDate = static_cast<std::uint16_t>(std::max(time.wYear - 1980, 0) << 9 |
                                                    time.wMonth << 5 | time.wDay);
    Manifest manifest{
        job.description,          created, job.environment.client, job.environment.game, {},
        lines(job.mods, maxMods), {}};
    for (const auto& line : lines(job.context, maxContext))
        if (const auto equal = line.find('='); equal != line.npos && equal)
            manifest.context.emplace_back(line.substr(0, equal), line.substr(equal + 1));
    const auto redacted = profiles();
    for (auto limit = maxFileBytes; limit >= minFileBytes; limit /= 2) {
        auto files = collect(job, limit, redacted);
        manifest.files.clear();
        for (const auto& file : files)
            manifest.files.push_back(file.name);
        const auto text = feedback::manifest(manifest);
        files.insert(files.begin(), {std::string(manifestName), {text.begin(), text.end()}});
        auto archive = zip(files, dosTime, dosDate);
        if (archive.size() + archiveHeadroom <= maxUploadBytes)
            return {std::move(archive), stamp};
    }
    throw std::runtime_error("logs exceed the upload limit");
}
std::string installId(const std::filesystem::path& directory) {
    const auto path = directory / L"install-id";
    std::string text;
    if (std::ifstream input(path, std::ios::binary); input)
        std::getline(input, text);
    text = trim(text);
    if (validUuid(text))
        return text;
    text = uuid(random16());
    // Best effort: an unsaved id only weakens per-install rate limiting.
    std::ofstream(path, std::ios::binary | std::ios::trunc) << text << "\n";
    return text;
}
std::pair<int, std::string> post(const std::wstring& endpoint,
                                 const std::vector<std::uint8_t>& body, const std::wstring& headers,
                                 const std::wstring& agent) {
    URL_COMPONENTS parts{};
    parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength =
        static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(endpoint.c_str(), 0, 0, &parts))
        return {0, {}};
    const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
    std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength);
    path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
    // System proxy settings first; older Windows only knows the default mode.
    Internet session{WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                 WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0)};
    if (!session.value)
        session.value = WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                    WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session.value ||
        !WinHttpSetTimeouts(session.value, resolveMs, connectMs, sendMs, receiveMs))
        return {0, {}};
    Internet connection{WinHttpConnect(session.value, host.c_str(), parts.nPort, 0)};
    if (!connection.value)
        return {0, {}};
    Internet request{
        WinHttpOpenRequest(connection.value, L"POST", path.c_str(), nullptr, WINHTTP_NO_REFERER,
                           WINHTTP_DEFAULT_ACCEPT_TYPES,
                           parts.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0)};
    const auto size = static_cast<DWORD>(body.size());
    if (!request.value ||
        !WinHttpSendRequest(request.value, headers.c_str(), static_cast<DWORD>(headers.size()),
                            const_cast<std::uint8_t*>(body.data()), size, size, 0) ||
        !WinHttpReceiveResponse(request.value, nullptr))
        return {0, {}};
    DWORD status = 0, length = sizeof(status);
    if (!WinHttpQueryHeaders(request.value, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status, &length,
                             WINHTTP_NO_HEADER_INDEX))
        return {0, {}};
    std::string response;
    char buffer[1024];
    DWORD read = 0;
    while (response.size() < maxResponseBytes &&
           WinHttpReadData(request.value, buffer, sizeof(buffer), &read) && read)
        response.append(buffer, std::min<std::size_t>(read, maxResponseBytes - response.size()));
    return {static_cast<int>(status), response};
}
void run(Job job) {
    std::pair<bool, std::string> result;
    std::filesystem::path saved;
    try {
        const auto directory = job.launch.parent_path().parent_path() / L"feedback";
        std::filesystem::create_directories(directory);
        const auto [archive, stamp] = package(job);
        const auto key = uuid(random16());
        const auto headers = wide("Content-Type: application/zip\r\nX-Feedback-Submission: " + key +
                                  "\r\nX-Feedback-Install: " + installId(directory) +
                                  "\r\nX-Feedback-Client: " + job.environment.client + "\r\n");
        // Keep a local copy until the receiver accepts it.
        saved = directory / wide(stamp + "-" + key.substr(0, 8) + ".zip");
        if (std::ofstream output(saved, std::ios::binary);
            !output.write(reinterpret_cast<const char*>(archive.data()),
                          static_cast<std::streamsize>(archive.size())))
            saved.clear();
        Outcome outcome;
        int status = 0;
        for (const auto delay : attempts) {
            std::this_thread::sleep_for(delay);
            std::string body;
            std::tie(status, body) = post(wide(job.environment.endpoint), archive, headers,
                                          wide(job.environment.client));
            outcome = interpret(status, body);
            if (!outcome.retry)
                break;
        }
        if (outcome.accepted) {
            std::error_code ignored;
            std::filesystem::remove(saved, ignored);
            saved.clear();
            logging::write("feedback_submitted id=" + outcome.id +
                           " bytes=" + std::to_string(archive.size()));
        } else {
            logging::write("feedback_upload_failure=" + std::to_string(status));
        }
        result = {outcome.accepted, outcome.text};
    } catch (const std::exception& error) {
        logging::write(std::string("feedback_package_failure=") + error.what());
        result = {false, "反馈打包失败"};
    }
    if (!result.first && !saved.empty())
        result.second += "。反馈包已保存到 " + utf8(saved) + "，可以直接发给作者";
    auto& state = shared();
    std::lock_guard lock(state.mutex);
    state.busy = false;
    state.result = std::move(result);
}

int reply(lua_State* L, bool ok, std::string_view message) {
    lua.pushBoolean(L, ok);
    lua.pushLString(L, message.data(), message.size());
    return 2;
}
std::string argument(lua_State* L, int index) {
    std::size_t length = 0;
    const char* text = lua.getTop(L) >= index ? lua.toString(L, index, &length) : nullptr;
    return text ? std::string(text, length) : std::string();
}
// feedback_submit(description, mods, context) -> ok, message. Mods and
// context ("key=value") are newline-separated lists.
int submit(lua_State* L) {
    std::size_t length = 0;
    const char* text = lua.checkString(L, 1, &length);
    const auto description = trim(std::string_view(text, length));
    if (!validDescription(description))
        return reply(L, false, "请在命令后写上问题描述");
    if (environment.endpoint.empty())
        return reply(L, false, "当前环境未启用反馈上传");
    const auto launch = logging::currentLaunch();
    if (launch.empty())
        return reply(L, false, "日志目录不可用，无法提交反馈");
    auto& state = shared();
    std::lock_guard lock(state.mutex);
    if (state.busy)
        return reply(L, false, "上一条反馈仍在上传，请稍候");
    const auto now = Clock::now();
    if (state.started && now - *state.started < cooldown)
        return reply(L, false, "反馈提交过于频繁，请稍后再试");
    try {
        std::thread(run, Job{description, argument(L, 2), argument(L, 3), launch, environment})
            .detach();
    } catch (const std::system_error&) {
        return reply(L, false, "无法启动反馈上传");
    }
    state.busy = true;
    state.result.reset();
    state.started = now;
    return reply(L, true, "正在收集日志并上传反馈……");
}
// feedback_poll() -> nothing while running, or accepted, message once.
int poll(lua_State* L) {
    auto& state = shared();
    std::lock_guard lock(state.mutex);
    if (!state.result)
        return 0;
    auto [accepted, message] = std::move(*state.result);
    state.result.reset();
    return reply(L, accepted, message);
}
} // namespace

bool configure(Environment value) {
    const bool valid = value.endpoint.empty() || validEndpoint(value.endpoint);
    if (!valid)
        value.endpoint.clear();
    environment = std::move(value);
    return valid;
}
bool bind(lua_State* L, HMODULE module) {
    if (!lua.load(module, {lua::Symbol::pushClosure, lua::Symbol::setField,
                           lua::Symbol::pushBoolean, lua::Symbol::pushLString,
                           lua::Symbol::checkString, lua::Symbol::toString, lua::Symbol::getTop}))
        return false;
    for (const auto& [name, function] :
         {std::pair<const char*, lua::Function>{"feedback_submit", submit},
          {"feedback_poll", poll}}) {
        lua.pushClosure(L, function, 0);
        lua.setField(L, -2, name);
    }
    return true;
}
} // namespace isaac::feedback

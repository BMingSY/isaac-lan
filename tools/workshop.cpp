// Windows x86 bridge to the game's public Steamworks API. No game process is started.
#include <windows.h>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>

namespace {
constexpr std::uint32_t appId = 250900;
constexpr int success = 1, queryCallback = 3401, submitCallback = 3404, downloadCallback = 3406;
constexpr ULONGLONG timeoutMs = 180000;
// SteamUGC020 / SteamUtils010, Windows SDK packing. The unused details tail is
// deliberately oversized; only the documented prefix is consumed.
#pragma pack(push, 8)
struct CallbackMessage {
    int user, callback;
    unsigned char* data;
    int size;
};
struct QueryResult {
    std::uint64_t query;
    int result;
    std::uint32_t returned, total;
    bool cached;
};
struct SubmitResult {
    int result;
    bool legal;
    std::uint64_t item;
};
struct DownloadResult {
    std::uint32_t app;
    std::uint64_t item;
    int result;
};
struct Details {
    std::uint64_t item;
    int result, fileType;
    std::uint32_t creator, consumer;
    char title[129], description[8000];
    std::uint64_t owner;
    std::uint32_t created, updated, added;
    int visibility;
    bool banned, accepted, tagsTruncated;
    unsigned char unused[8192];
};
#pragma pack(pop)
static_assert(sizeof(void*) == 4 && sizeof(QueryResult) == 24 && sizeof(SubmitResult) == 16);
static_assert(sizeof(DownloadResult) == 24 && offsetof(Details, owner) == 8160);

std::string utf8(const std::wstring& value) {
    const int size =
        WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                            static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (!size && !value.empty())
        throw std::runtime_error("Invalid Unicode argument");
    std::string result(size, '\0');
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(), static_cast<int>(value.size()),
                        result.data(), size, nullptr, nullptr);
    return result;
}
std::string quote(const std::string& value) {
    std::string result = "\"";
    for (unsigned char c : value) {
        if (c == '\\' || c == '"')
            result += '\\';
        if (c < 32) {
            char escaped[7];
            std::snprintf(escaped, sizeof(escaped), "\\u%04x", c);
            result += escaped;
        } else
            result += static_cast<char>(c);
    }
    return result + '"';
}
std::string read(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    if (!file)
        throw std::runtime_error("Cannot read notes");
    return {std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>()};
}
void write(const std::filesystem::path& prefix, const std::string& json) {
    auto path = prefix;
    path += L".json";
    std::ofstream out(path, std::ios::binary);
    out << json << '\n';
    out.close();
    if (!out)
        throw std::runtime_error("Cannot write Steam result");
}

struct Steam {
    HMODULE dll = nullptr;
    bool initialized = false;
    void(__cdecl* shutdown)() = nullptr;
    void *ugc = nullptr, *utils = nullptr;
    int pipe = 0;
    template <class T> T function(const char* name) {
        auto address = GetProcAddress(dll, name);
        if (!address)
            throw std::runtime_error(std::string("Steam export missing: ") + name);
        static_assert(sizeof(T) == sizeof(address));
        T result{};
        std::memcpy(&result, &address, sizeof(result));
        return result;
    }
    ~Steam() {
        if (initialized)
            shutdown();
        if (dll)
            FreeLibrary(dll);
    }
    void open(const std::filesystem::path& path) {
        const auto app = std::to_wstring(appId);
        SetEnvironmentVariableW(L"SteamAppId", app.c_str());
        SetEnvironmentVariableW(L"SteamGameId", app.c_str());
        dll = LoadLibraryExW(path.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
        if (!dll)
            throw std::runtime_error("Cannot load the game's steam_api.dll");
        shutdown = function<void(__cdecl*)()>("SteamAPI_Shutdown");
        char error[1024]{};
        if (function<int(__cdecl*)(char*)>("SteamAPI_InitFlat")(error) != 0)
            throw std::runtime_error(error);
        initialized = true;
        ugc = function<void*(__cdecl*)()>("SteamAPI_SteamUGC_v020")();
        utils = function<void*(__cdecl*)()>("SteamAPI_SteamUtils_v010")();
        if (!ugc || !utils)
            throw std::runtime_error("Steam interface unavailable");
        function<void(__cdecl*)()>("SteamAPI_ManualDispatch_Init")();
        pipe = function<int(__cdecl*)()>("SteamAPI_GetHSteamPipe")();
    }
    template <class F> void callbacks(F consume) {
        function<void(__cdecl*)(int)>("SteamAPI_ManualDispatch_RunFrame")(pipe);
        CallbackMessage message{};
        while (function<bool(__cdecl*)(int, CallbackMessage*)>(
            "SteamAPI_ManualDispatch_GetNextCallback")(pipe, &message)) {
            consume(message);
            function<void(__cdecl*)(int)>("SteamAPI_ManualDispatch_FreeLastCallback")(pipe);
        }
    }
    template <class T> void wait(std::uint64_t call, int callback, T& result) {
        if (!call)
            throw std::runtime_error("Steam async call invalid");
        const auto deadline = GetTickCount64() + timeoutMs;
        while (GetTickCount64() < deadline) {
            callbacks([](const CallbackMessage&) {});
            bool failed = false;
            if (function<bool(__cdecl*)(void*, std::uint64_t, bool*)>(
                    "SteamAPI_ISteamUtils_IsAPICallCompleted")(utils, call, &failed)) {
                if (failed ||
                    !function<bool(__cdecl*)(int, std::uint64_t, void*, int, int, bool*)>(
                        "SteamAPI_ManualDispatch_GetAPICallResult")(
                        pipe, call, &result, sizeof(result), callback, &failed) ||
                    failed)
                    throw std::runtime_error("Steam async result unavailable");
                return;
            }
            Sleep(100);
        }
        throw std::runtime_error("Steam timeout; inspect the remote item before retrying");
    }
    void query(std::uint64_t item, const std::filesystem::path& output,
               const std::string& language) {
        const auto handle =
            function<std::uint64_t(__cdecl*)(void*, const std::uint64_t*, std::uint32_t)>(
                "SteamAPI_ISteamUGC_CreateQueryUGCDetailsRequest")(ugc, &item, 1);
        if (handle == UINT64_MAX)
            throw std::runtime_error("Invalid query");
        // The process owns this one query; always release it before returning.
        try {
            if (!function<bool(__cdecl*)(void*, std::uint64_t, std::uint32_t)>(
                    "SteamAPI_ISteamUGC_SetAllowCachedResponse")(ugc, handle, 0) ||
                !function<bool(__cdecl*)(void*, std::uint64_t, bool)>(
                    "SteamAPI_ISteamUGC_SetReturnLongDescription")(ugc, handle, true) ||
                !function<bool(__cdecl*)(void*, std::uint64_t, const char*)>(
                    "SteamAPI_ISteamUGC_SetLanguage")(ugc, handle, language.c_str()))
                throw std::runtime_error("Query options rejected");
            QueryResult result{};
            wait(function<std::uint64_t(__cdecl*)(void*, std::uint64_t)>(
                     "SteamAPI_ISteamUGC_SendQueryUGCRequest")(ugc, handle),
                 queryCallback, result);
            Details details{};
            if (result.result != success || result.returned != 1 ||
                !function<bool(__cdecl*)(void*, std::uint64_t, std::uint32_t, void*)>(
                    "SteamAPI_ISteamUGC_GetQueryUGCResult")(ugc, handle, 0, &details) ||
                details.item != item || details.result != success || details.consumer != appId ||
                details.creator != appId || !std::memchr(details.title, 0, sizeof(details.title)) ||
                !std::memchr(details.description, 0, sizeof(details.description)))
                throw std::runtime_error("Unexpected Workshop identity or details layout");
            write(output, "{\"item_id\":" + quote(std::to_string(item)) +
                              ",\"owner\":" + quote(std::to_string(details.owner)) +
                              ",\"title\":" + quote(details.title) +
                              ",\"description\":" + quote(details.description) +
                              ",\"updated\":" + std::to_string(details.updated) +
                              ",\"visibility\":" + std::to_string(details.visibility) +
                              ",\"banned\":" + (details.banned ? "true" : "false") + "}");
        } catch (...) {
            function<bool(__cdecl*)(void*, std::uint64_t)>(
                "SteamAPI_ISteamUGC_ReleaseQueryUGCRequest")(ugc, handle);
            throw;
        }
        function<bool(__cdecl*)(void*, std::uint64_t)>("SteamAPI_ISteamUGC_ReleaseQueryUGCRequest")(
            ugc, handle);
    }
    void update(std::uint64_t item, const std::filesystem::path& output, const std::string& content,
                const std::filesystem::path& notesPath) {
        const auto notes = read(notesPath);
        if (notes.empty() || notes.find('\0') != std::string::npos)
            throw std::runtime_error("Change notes are empty or invalid");
        const auto handle = function<std::uint64_t(__cdecl*)(void*, std::uint32_t, std::uint64_t)>(
            "SteamAPI_ISteamUGC_StartItemUpdate")(ugc, appId, item);
        if (handle == UINT64_MAX ||
            !function<bool(__cdecl*)(void*, std::uint64_t, const char*)>(
                "SteamAPI_ISteamUGC_SetItemContent")(ugc, handle, content.c_str()))
            throw std::runtime_error("Workshop content rejected");
        // Only content and change notes: preserve title, descriptions, visibility and preview.
        SubmitResult result{};
        wait(function<std::uint64_t(__cdecl*)(void*, std::uint64_t, const char*)>(
                 "SteamAPI_ISteamUGC_SubmitItemUpdate")(ugc, handle, notes.c_str()),
             submitCallback, result);
        write(output, "{\"item_id\":" + quote(std::to_string(result.item)) +
                          ",\"result\":" + std::to_string(result.result) +
                          ",\"legal_agreement_required\":" + (result.legal ? "true" : "false") +
                          "}");
        if (result.item != item || result.result != success || result.legal)
            throw std::runtime_error("Steam rejected the update or requires its legal agreement");
    }
    void download(std::uint64_t item, const std::filesystem::path& output) {
        if (!function<bool(__cdecl*)(void*, std::uint64_t, bool)>(
                "SteamAPI_ISteamUGC_DownloadItem")(ugc, item, false))
            throw std::runtime_error("Cannot request Workshop download");
        bool complete = false;
        int result = 0;
        const auto deadline = GetTickCount64() + timeoutMs;
        while (!complete && GetTickCount64() < deadline) {
            callbacks([&](const CallbackMessage& message) {
                if (message.callback != downloadCallback ||
                    message.size < static_cast<int>(sizeof(DownloadResult)))
                    return;
                DownloadResult value{};
                std::memcpy(&value, message.data, sizeof(value));
                if (value.app == appId && value.item == item) {
                    complete = true;
                    result = value.result;
                }
            });
            if (!complete)
                Sleep(100);
        }
        if (!complete || result != success)
            throw std::runtime_error("Workshop download failed or timed out");
        char folder[4096]{};
        std::uint64_t bytes = 0;
        std::uint32_t updated = 0;
        if (!function<bool(__cdecl*)(void*, std::uint64_t, std::uint64_t*, char*, std::uint32_t,
                                     std::uint32_t*)>("SteamAPI_ISteamUGC_GetItemInstallInfo")(
                ugc, item, &bytes, folder, sizeof(folder), &updated))
            throw std::runtime_error("Downloaded folder unavailable");
        write(output, "{\"item_id\":" + quote(std::to_string(item)) +
                          ",\"folder\":" + quote(folder) + ",\"bytes\":" + std::to_string(bytes) +
                          ",\"updated\":" + std::to_string(updated) + "}");
    }
};
} // namespace

int wmain(int argc, wchar_t** argv) {
    try {
        if (argc < 5)
            throw std::runtime_error("Usage: workshop.exe query|download|update STEAM_API_DLL "
                                     "ITEM_ID OUTPUT_PREFIX [LANGUAGE | CONTENT NOTES]");
        const std::wstring command = argv[1];
        if (!((command == L"query" && argc == 6) || (command == L"download" && argc == 5) ||
              (command == L"update" && argc == 7)))
            throw std::runtime_error("Invalid Workshop command arguments");
        std::size_t end = 0;
        const std::uint64_t item = std::stoull(argv[3], &end);
        if (!item || end != std::wstring(argv[3]).size())
            throw std::runtime_error("Invalid Workshop item ID");
        Steam steam;
        steam.open(std::filesystem::absolute(argv[2]));
        if (command == L"query")
            steam.query(item, argv[4], utf8(argv[5]));
        else if (command == L"download")
            steam.download(item, argv[4]);
        else
            steam.update(item, argv[4], utf8(std::filesystem::absolute(argv[5]).wstring()),
                         argv[6]);
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

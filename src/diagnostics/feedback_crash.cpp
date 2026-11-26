#include "diagnostics/feedback_crash.h"
#include "core/feedback.h"
#include <windows.h>
#include <dbghelp.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>

namespace isaac::feedback {
namespace {
namespace fs = std::filesystem;
constexpr std::size_t launchStampLength = 15; // YYYYMMDD-HHMMSS, local time in both filenames
constexpr std::size_t launchPidStart = 21;    // YYYYMMDD-HHMMSS-mmm-p
constexpr unsigned maxStreams = 128, maxModules = 4096, maxModulePathUnits = 32768;
constexpr std::uint32_t dumpSignature = 0x504d444d; // MDMP in little endian

std::string launchBuild(const fs::path& launch, std::string_view fallback) {
    std::ifstream log(launch / L"startup.log", std::ios::binary);
    std::array<char, 8192> prefix{};
    log.read(prefix.data(), prefix.size());
    const std::string_view text(prefix.data(), static_cast<std::size_t>(log.gcount()));
    // An update between launches can change the game build as well as the Mod.
    for (const std::string_view marker :
         {"game_compatibility=PASS build=", "bootstrap=PASS version="}) {
        if (const auto at = text.find(marker); at != text.npos) {
            const auto rest = text.substr(at + marker.size());
            return std::string(rest.substr(0, rest.find_first_of(" \t\r\n")));
        }
    }
    return std::string(fallback);
}

bool directFile(const fs::path& path, bool directory = false) {
    const auto flags = GetFileAttributesW(path.c_str());
    return flags != INVALID_FILE_ATTRIBUTES && !(flags & FILE_ATTRIBUTE_REPARSE_POINT) &&
           static_cast<bool>(flags & FILE_ATTRIBUTE_DIRECTORY) == directory;
}
bool decimal(std::string_view value) {
    return !value.empty() && value.find_first_not_of("0123456789") == value.npos;
}
bool matches(std::string_view stem, std::string_view prefix, std::string_view pid,
             std::string_view start, std::string_view end) {
    if (!stem.starts_with(prefix))
        return false;
    stem.remove_prefix(prefix.size());
    const auto stamp = stem.substr(0, launchStampLength);
    if (stem.size() <= launchStampLength || stem[launchStampLength] != '-' || stamp < start ||
        stamp > end || stamp[8] != '-' || !decimal(stamp.substr(0, 8)) || !decimal(stamp.substr(9)))
        return false;
    const auto ids = stem.substr(launchStampLength + 1);
    const auto dash = ids.find('-');
    return dash != ids.npos && ids.substr(0, dash) == pid && decimal(ids.substr(dash + 1));
}

// Read only fixed-size records and the faulting module's name. A 32-bit game process
// can inspect very large dumps without mapping or loading their memory streams.
class Dump {
    std::ifstream stream;
    std::uint64_t size = 0;

  public:
    explicit Dump(const fs::path& path) : stream(path, std::ios::binary | std::ios::ate) {
        if (const auto end = stream.tellg(); end >= 0)
            size = static_cast<std::uint64_t>(end);
    }
    bool read(std::uint64_t offset, void* buffer, std::size_t bytes) {
        if (offset > size || bytes > size - offset)
            return false;
        return static_cast<bool>(stream.seekg(static_cast<std::streamoff>(offset))
                                     .read(static_cast<char*>(buffer), bytes));
    }
    template <typename T> bool read(std::uint64_t offset, T& record) {
        return read(offset, &record, sizeof(record));
    }
    std::string moduleName(std::uint32_t offset) {
        ULONG32 bytes{};
        if (!read(offset, bytes) || bytes == 0 || bytes % sizeof(wchar_t) ||
            bytes / sizeof(wchar_t) > maxModulePathUnits)
            return {};
        std::wstring path(bytes / sizeof(wchar_t), L'\0');
        if (!read(std::uint64_t(offset) + sizeof(bytes), path.data(), bytes) ||
            path.find(L'\0') != path.npos)
            return {};
        const auto name = fs::path(path).filename().wstring();
        if (name.empty() || name.size() > 255)
            return {};
        std::array<char, 1024> utf8{};
        const int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, name.data(),
                                               static_cast<int>(name.size()), utf8.data(),
                                               static_cast<int>(utf8.size()), nullptr, nullptr);
        return printable(std::string_view(utf8.data(), length));
    }
};

std::string hex(std::uint32_t value) {
    char text[11]{};
    std::snprintf(text, sizeof(text), "0x%08x", static_cast<unsigned>(value));
    return text;
}
std::string dumpSummary(const fs::path& path) {
    Dump dump(path);
    MINIDUMP_HEADER header{};
    if (!dump.read(0, header) || header.Signature != dumpSignature ||
        LOWORD(header.Version) != MINIDUMP_VERSION || header.NumberOfStreams > maxStreams)
        return {};
    MINIDUMP_LOCATION_DESCRIPTOR exception{}, modules{};
    for (unsigned i = 0; i < header.NumberOfStreams; ++i) {
        MINIDUMP_DIRECTORY entry{};
        if (!dump.read(std::uint64_t(header.StreamDirectoryRva) + i * sizeof(entry), entry))
            return {};
        if (entry.StreamType == ExceptionStream)
            exception = entry.Location;
        if (entry.StreamType == ModuleListStream)
            modules = entry.Location;
    }
    MINIDUMP_EXCEPTION_STREAM fault{};
    if (exception.DataSize < sizeof(fault) || !dump.read(exception.Rva, fault))
        return {};
    const auto& record = fault.ExceptionRecord;
    std::string fields = "\"exceptionCode\":" + jsonString(hex(record.ExceptionCode));
    ULONG32 count{};
    if (modules.DataSize >= sizeof(count) && dump.read(modules.Rva, count) && count <= maxModules &&
        count <= (modules.DataSize - sizeof(count)) / sizeof(MINIDUMP_MODULE)) {
        for (unsigned i = 0; i < count; ++i) {
            MINIDUMP_MODULE module{};
            if (!dump.read(std::uint64_t(modules.Rva) + sizeof(count) + i * sizeof(module), module))
                break;
            if (record.ExceptionAddress < module.BaseOfImage ||
                record.ExceptionAddress - module.BaseOfImage >= module.SizeOfImage)
                continue;
            const auto name = dump.moduleName(module.ModuleNameRva);
            if (!name.empty()) {
                fields += ",\"module\":" + jsonString(name) + ",\"rva\":" +
                          jsonString(hex(static_cast<std::uint32_t>(record.ExceptionAddress -
                                                                    module.BaseOfImage)));
            }
            break;
        }
    }
    return "{" + fields + "}\n";
}
} // namespace

CrashReport previousCrash(const fs::path& previousLaunch, const fs::path& currentLaunch,
                          std::string_view gameBuild) {
    const auto previous = previousLaunch.filename().string(),
               current = currentLaunch.filename().string();
    if (!launchName(previous) || !launchName(current) || previous >= current)
        return {};
    const auto directory = currentLaunch.parent_path().parent_path().parent_path() / L"crash_dumps";
    if (!directFile(directory, true))
        return {};
    const auto prefix = "isaacv" + launchBuild(previousLaunch, gameBuild) + "-";
    const auto start = std::string_view(previous).substr(0, launchStampLength);
    const auto end = std::string_view(current).substr(0, launchStampLength);
    auto pid = std::string_view(previous).substr(launchPidStart);
    pid = pid.substr(0, pid.find('-'));
    std::string selected;
    std::error_code error;
    for (fs::directory_iterator it(directory, error), last; !error && it != last;
         it.increment(error)) {
        const auto& path = it->path();
        if (path.extension() != L".txt" && path.extension() != L".dmp")
            continue;
        const auto name = path.stem().wstring();
        if (std::any_of(name.begin(), name.end(), [](wchar_t c) { return c > 127; }))
            continue;
        const std::string stem(name.begin(), name.end());
        if (stem > selected && matches(stem, prefix, pid, start, end) && directFile(path))
            selected = stem;
    }
    if (selected.empty())
        return {};
    CrashReport result;
    const auto log = directory / (selected + ".txt"), dump = directory / (selected + ".dmp");
    if (directFile(log))
        result.log = log;
    if (directFile(dump))
        result.summary = dumpSummary(dump);
    return result;
}
} // namespace isaac::feedback

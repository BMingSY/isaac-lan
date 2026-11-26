#include "diagnostics/feedback_crash.h"
#include "test_support.h"
#include <windows.h>
#include <dbghelp.h>
#include <winioctl.h>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <vector>

namespace fs = std::filesystem;
namespace {
template <typename T> unsigned append(std::vector<char>& bytes, const T& value) {
    const auto offset = static_cast<unsigned>(bytes.size());
    const char* first = reinterpret_cast<const char*>(&value);
    bytes.insert(bytes.end(), first, first + sizeof(value));
    return offset;
}
void writeDump(const fs::path& path, unsigned exceptionCode) {
    MINIDUMP_HEADER header{};
    std::memcpy(&header.Signature, "MDMP", 4);
    header.Version = MINIDUMP_VERSION;
    header.NumberOfStreams = 2;
    header.StreamDirectoryRva = sizeof(header);
    MINIDUMP_DIRECTORY streams[2]{};
    std::vector<char> bytes;
    append(bytes, header);
    append(bytes, streams);
    MINIDUMP_EXCEPTION_STREAM fault{};
    fault.ExceptionRecord.ExceptionCode = exceptionCode;
    fault.ExceptionRecord.ExceptionAddress = 0x12345678;
    streams[0] = {ExceptionStream, {sizeof(fault), append(bytes, fault)}};
    MINIDUMP_MODULE module{};
    module.BaseOfImage = 0x12345000;
    module.SizeOfImage = 0x1000;
    const std::wstring modulePath = L"C:\\Users\\PRIVATE\\isaac-ng.exe";
    module.ModuleNameRva = append(bytes, static_cast<ULONG32>(modulePath.size() * sizeof(wchar_t)));
    bytes.insert(bytes.end(), reinterpret_cast<const char*>(modulePath.data()),
                 reinterpret_cast<const char*>(modulePath.data() + modulePath.size()));
    streams[1] = {ModuleListStream, {sizeof(ULONG32) + sizeof(module), append(bytes, ULONG32{1})}};
    append(bytes, module);
    std::memcpy(bytes.data() + header.StreamDirectoryRva, streams, sizeof(streams));
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file.write(bytes.data(), bytes.size());
}
void matchingCrash() {
    const auto root =
        fs::temp_directory_path() / ("isaac-crash-report-" + std::to_string(GetCurrentProcessId()) +
                                     "-" + std::to_string(GetTickCount64()));
    struct Cleanup {
        fs::path root;
        ~Cleanup() {
            std::error_code ignored;
            fs::remove_all(root, ignored);
        }
    } cleanup{root};
    const auto logs = root / "isaac-lan/logs", dumps = root / "crash_dumps";
    const auto previous = logs / "20261125-230050-267-p27612-1";
    const auto current = logs / "20261126-001000-720-p25868";
    fs::create_directories(previous);
    fs::create_directories(current);
    fs::create_directories(dumps);
    std::ofstream(previous / "startup.log")
        << "header\n[INFO] game_compatibility=PASS build=1.9.7.19.J511\n";
    const std::string stem = "isaacv1.9.7.19.J511-20261125-234957-27612-9";
    for (const auto* decoy :
         {"isaacv1.9.7.19.J511-20261125-220000-27612-9", // reused PID before launch
          "isaacv1.9.7.19.J511-20261126-001001-27612-9", // after next launch
          "isaacv1.9.7.19.J511-20261125-235100-27613-9", // other process
          "isaacv1.9.7.20.J521-20261125-235100-27612-9", // wrong executable build
          "isaacv1.9.7.19.J511-20261125-235100-27612-other"}) {
        std::ofstream(dumps / (std::string(decoy) + ".txt")) << "unrelated";
    }
    auto report = [&] {
        return isaac::feedback::previousCrash(previous, current, "1.9.7.20.J521");
    };
    require(report().log.empty(), "Selected an unrelated crash");
    const auto log = dumps / (stem + ".txt"), dump = dumps / (stem + ".dmp");
    std::ofstream(log) << "Lua stack trace";
    require(report().log == log && report().summary.empty(), "Text-only crash was lost");
    writeDump(dump, EXCEPTION_ACCESS_VIOLATION);
    const auto summary = report().summary;
    require(summary == "{\"exceptionCode\":\"0xc0000005\",\"module\":\"isaac-ng.exe\",\"rva\":"
                       "\"0x00000678\"}\n",
            "Unexpected module, offset, exception or private data in summary");
    // On filesystems supporting sparse files, exceed the address space of the x86
    // client. The metadata remains small and the dump never needs to be mapped.
    const HANDLE file = CreateFileW(dump.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
                                    FILE_ATTRIBUTE_NORMAL, nullptr);
    require(file != INVALID_HANDLE_VALUE, "Cannot open sparse dump fixture");
    DWORD returned = 0;
    const bool sparse =
        DeviceIoControl(file, FSCTL_SET_SPARSE, nullptr, 0, nullptr, 0, &returned, nullptr);
    CloseHandle(file);
    if (sparse) {
        fs::resize_file(dump, 3ull * 1024 * 1024 * 1024);
        require(report().summary == summary, "Large dump suppressed its bounded summary");
    }
    fs::remove(log);
    require(report().log.empty() && report().summary == summary, "Dump-only report was lost");
    std::ofstream(log) << "keep this text";
    fs::resize_file(dump, sizeof(MINIDUMP_HEADER) + 1);
    require(report().log == log && report().summary.empty(),
            "Truncated dump suppressed crash text");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"previous-launch", matchingCrash}});
}

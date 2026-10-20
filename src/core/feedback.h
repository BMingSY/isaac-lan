#pragma once
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

// Portable rules for /feedback packages: zip layout, log selection and
// redaction, the manifest, and interpretation of the receiver's responses.
// The upload contract is owned by the isaac-lan-feedback service (API v1).
namespace isaac::feedback {
inline constexpr std::string_view defaultEndpoint =
    "https://lzh-qwq.top/isaac-lan/feedback/v1/submit";
inline constexpr std::size_t maxUploadBytes = 10 * 1024 * 1024;
inline constexpr std::size_t maxDescriptionBytes = 4096;
inline constexpr std::size_t maxEndpointBytes = 512;
// Each log keeps its newest bytes; the cap halves until the zip fits.
inline constexpr std::size_t maxFileBytes = 8 * 1024 * 1024, minFileBytes = 256 * 1024;
inline constexpr std::size_t collectedLaunches = 2;
inline constexpr std::string_view manifestName = "feedback.json";
inline constexpr std::string_view redactedProfile = "%USERPROFILE%";

struct File {
    std::string name;
    std::vector<std::uint8_t> data;
};
struct Manifest {
    std::string description, createdAt, client, game;
    std::vector<std::pair<std::string, std::string>> context;
    std::vector<std::string> mods, files;
};
struct Outcome {
    bool accepted = false;
    // Transient transport or server failure; the same submission may be resent.
    bool retry = false;
    std::string id, text;
};

bool safeName(std::string_view name);
// Deflate (or store) each file; MS-DOS time and date stamp every entry.
std::vector<std::uint8_t> zip(std::span<const File> files, std::uint16_t dosTime,
                              std::uint16_t dosDate);
// Keep the newest bytes from a line boundary, marking what was dropped.
// omitted counts bytes before text that the caller never read.
std::string tail(std::string_view text, std::size_t limit, std::size_t omitted = 0);
// Replace the Windows profile path (either separator, ASCII case-insensitive)
// and Steam account directories in collected logs.
std::string redact(std::string_view text, std::span<const std::string> profiles);
// Launch directory names to collect: the current launch and the one before it.
std::vector<std::string> launches(std::vector<std::string> names, std::string_view current);
bool launchName(std::string_view name);
bool validDescription(std::string_view text);
bool validEndpoint(std::string_view endpoint);
bool validUuid(std::string_view text);
bool validId(std::string_view text);
std::string uuid(std::span<const std::uint8_t, 16> random);
// Valid UTF-8 without control characters; other bytes become '?'.
std::string printable(std::string_view text);
std::string jsonString(std::string_view text);
std::string manifest(const Manifest& value);
std::optional<std::string> jsonField(std::string_view json, std::string_view key);
// status 0 means the request never received an HTTP response.
Outcome interpret(int status, std::string_view body);
} // namespace isaac::feedback

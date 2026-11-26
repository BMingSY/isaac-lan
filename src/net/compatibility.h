#pragma once
#include "net/datagram_protocol.h"
#include "core/lua_version.h"
#include "net/protocol.h"

namespace isaac::lan {
// This uncompressed, reliable preflight is independent of the gameplay protocol.
// Keep its envelope, revision and field order stable across gameplay revisions.
inline constexpr std::uint32_t compatibilityConnectData = 0x494c414e; // ILAN
inline constexpr std::uint16_t compatibilityRevision = 1;
inline constexpr std::size_t maxVersionLength = 32, maxFingerprintLength = 128;
inline constexpr std::size_t maxCompatibilitySize =
    1 + 2 + 2 + 2 + maxVersionLength + 2 + maxFingerprintLength;
// Unqualified game build hashes belong to the original Lua runtime. Qualify
// the alternate runtime inside the existing fingerprint field so older peers
// can still read the preflight and report a version or build mismatch.
inline constexpr std::string_view lua54Prefix = "lua5.4/";
inline std::string runtimeFingerprint(std::string_view build, lua::Version runtime) {
    if (build.empty())
        return {};
    std::string result;
    if (runtime == lua::Version::v54)
        result = lua54Prefix;
    result += build;
    return result;
}
inline lua::Version fingerprintRuntime(std::string_view fingerprint) {
    return fingerprint.starts_with(lua54Prefix) ? lua::Version::v54 : lua::Version::v53;
}
struct BuildIdentity {
    std::string version, fingerprint;
    std::uint16_t protocol = protocolVersion;
    bool valid() const {
        return !version.empty() && version.size() <= maxVersionLength &&
               std::all_of(version.begin(), version.end(),
                           [](char c) {
                               return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
                                      (c >= 'A' && c <= 'Z') || c == '.' || c == '-' || c == '+';
                           }) &&
               !fingerprint.empty() && fingerprint.size() <= maxFingerprintLength &&
               std::all_of(fingerprint.begin(), fingerprint.end(),
                           [](unsigned char c) { return c >= '!' && c <= '~'; });
    }
    bool operator==(const BuildIdentity&) const = default;
};
enum class CompatibilityIssue { version, fingerprint, protocol, luaRuntime, unavailable };
inline const char* compatibilityName(CompatibilityIssue issue) {
    switch (issue) {
    case CompatibilityIssue::version:
        return "version";
    case CompatibilityIssue::fingerprint:
        return "fingerprint";
    case CompatibilityIssue::luaRuntime:
        return "luaRuntime";
    case CompatibilityIssue::protocol:
        return "protocol";
    case CompatibilityIssue::unavailable:
        return "unavailable";
    }
    return "unavailable";
}
struct CompatibilityFailure {
    CompatibilityIssue issue;
    std::string localVersion, remoteVersion;
    std::string message() const {
        return std::string("Isaac LAN compatibility check failed: ") + compatibilityName(issue) +
               " (local=" + localVersion +
               ", peer=" + (remoteVersion.empty() ? "unknown" : remoteVersion) + ")";
    }
};
inline std::optional<CompatibilityFailure> checkCompatibility(const BuildIdentity& local,
                                                              const BuildIdentity& remote) {
    if (!local.valid() || !remote.valid())
        return CompatibilityFailure{CompatibilityIssue::unavailable, local.version, {}};
    if (local.version != remote.version)
        return CompatibilityFailure{CompatibilityIssue::version, local.version, remote.version};
    const auto localLua = fingerprintRuntime(local.fingerprint);
    const auto remoteLua = fingerprintRuntime(remote.fingerprint);
    if (localLua != remoteLua)
        return CompatibilityFailure{CompatibilityIssue::luaRuntime, lua::versionName(localLua),
                                    lua::versionName(remoteLua)};
    if (local.fingerprint != remote.fingerprint)
        return CompatibilityFailure{CompatibilityIssue::fingerprint, local.version, remote.version};
    if (local.protocol != remote.protocol)
        return CompatibilityFailure{CompatibilityIssue::protocol, local.version, remote.version};
    return {};
}
inline std::vector<std::uint8_t> compatibilityPacket(const BuildIdentity& build) {
    if (!build.valid())
        throw std::runtime_error("Invalid local build identity");
    Writer writer(static_cast<Message>(datagram::Envelope::compatibility));
    writer.u16(compatibilityRevision);
    writer.u16(build.protocol);
    writer.string(build.version);
    writer.string(build.fingerprint);
    return std::move(writer.bytes);
}
inline BuildIdentity readCompatibility(std::span<const std::uint8_t> bytes) {
    if (bytes.size() > maxCompatibilitySize)
        throw std::runtime_error("Oversized compatibility packet");
    Reader reader(bytes);
    if (reader.u8() != static_cast<unsigned>(datagram::Envelope::compatibility) ||
        reader.u16() != compatibilityRevision)
        throw std::runtime_error("Unsupported compatibility preflight");
    BuildIdentity result;
    result.protocol = reader.u16();
    result.version = reader.string();
    result.fingerprint = reader.string();
    reader.finish();
    if (!result.valid())
        throw std::runtime_error("Invalid remote build identity");
    return result;
}
} // namespace isaac::lan

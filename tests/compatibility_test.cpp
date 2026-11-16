#include "net/compatibility.h"
#include "test_support.h"
using namespace isaac::lan;
namespace {
void contract() {
    const BuildIdentity local{"0.6.0", "dll-fingerprint"};
    require(readCompatibility(compatibilityPacket(local)) == local,
            "Build identity changed on wire");
    // Frozen preflight framing, independent of the current gameplay protocol.
    const std::vector<std::uint8_t> fixture{5,   0,   1,   0, 45, 0,   5,   '0', '.',
                                            '5', '.', '1', 0, 3,  'a', 'b', 'c'};
    require(readCompatibility(fixture) == BuildIdentity{"0.5.1", "abc", 45},
            "Preflight can no longer read a different gameplay protocol");
    require(compatibilityPacket({"0.5.1", "abc", 45}) == fixture,
            "Preflight wire contract changed");
    require(!checkCompatibility(local, local), "Identical builds rejected");
    for (const auto& version : {"0.6.1", "0.6.0-rc.1", "0.6.0+test", "0.6.00"}) {
        const auto failure = checkCompatibility(local, {version, local.fingerprint});
        require(failure && failure->issue == CompatibilityIssue::version &&
                    failure->localVersion == local.version && failure->remoteVersion == version,
                "Different complete version was admitted or lost its version details");
        require(failure->message().find(version) != std::string::npos &&
                    failure->message().find(local.version) != std::string::npos,
                "Failure log lost version details");
    }
    require(checkCompatibility(local, {local.version, "different-dll"})->issue ==
                CompatibilityIssue::fingerprint,
            "Same version bypassed DLL fingerprint check");
    require(
        checkCompatibility(local, {local.version, local.fingerprint, protocolVersion + 1})->issue ==
            CompatibilityIssue::protocol,
        "Same build bypassed protocol check");
}
void malformed() {
    const auto packet = compatibilityPacket({"0.6.0", "dll-fingerprint"});
    for (std::size_t size = 0; size < packet.size(); ++size)
        rejects([&] { readCompatibility(std::span(packet).first(size)); },
                "Truncated preflight accepted");
    auto changed = packet;
    changed.push_back(0);
    rejects([&] { readCompatibility(changed); }, "Trailing preflight data accepted");
    changed[0] = static_cast<unsigned>(datagram::Envelope::message);
    rejects([&] { readCompatibility(changed); }, "Legacy gameplay envelope accepted as preflight");
    changed = packet;
    changed[2] = compatibilityRevision + 1;
    rejects([&] { readCompatibility(changed); }, "Unknown preflight revision accepted");
    changed.assign(maxCompatibilitySize + 1, 0);
    rejects([&] { readCompatibility(changed); }, "Oversized preflight accepted");
    for (const auto& version :
         {std::string{}, std::string(maxVersionLength + 1, '1'), std::string("0.6.0\nforged log"),
          std::string("0.6.0\0suffix", 12)}) {
        rejects([&] { compatibilityPacket({version, "dll"}); }, "Invalid local version accepted");
        Writer raw(static_cast<Message>(datagram::Envelope::compatibility));
        raw.u16(compatibilityRevision);
        raw.u16(protocolVersion);
        raw.string(version);
        raw.string("dll");
        rejects([&] { readCompatibility(raw.bytes); }, "Invalid remote version accepted");
    }
    for (const auto& fingerprint :
         {std::string{}, std::string(maxFingerprintLength + 1, 'f'), std::string("fingerprint\n")})
        rejects([&] { compatibilityPacket({"0.6.0", fingerprint}); },
                "Invalid fingerprint accepted");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv, {{"contract", contract}, {"malformed", malformed}});
}

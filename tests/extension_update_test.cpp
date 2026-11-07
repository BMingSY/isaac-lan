#include "core/extension_package.h"
#include "runtime/extension_update.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <random>
#include <stdexcept>

namespace {
namespace fs = std::filesystem;
using namespace isaac::updates;
constexpr auto gameBuild = "1.9.7.17.J460";
fs::path sourceToChange;
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
std::string read(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
void write(const fs::path& path, const std::string& value) {
    fs::create_directories(path.parent_path());
    std::ofstream(path, std::ios::binary) << value;
}
// Deterministic hash stand-in lets portable tests inject copy/read failures.
// The Windows loader tests additionally use actual BCrypt SHA-256 and DLLs.
std::string hash(const fs::path& path) {
    const auto bytes = read(path);
    return std::string(64, bytes == "new" ? 'a' : bytes == "next" ? 'b' : 'c');
}
std::string manifest(const std::string& version = "0.6.4", const std::string& bytes = "new",
                     const std::string& build = gameBuild, unsigned abi = loaderABI) {
    const auto digest = std::string(64, bytes == "new" ? 'a' : bytes == "next" ? 'b' : 'c');
    return std::string(manifestMagic) + "\nversion=" + version + "\ngame_build=" + build +
           "\nloader_abi=" + std::to_string(abi) + "\nsha256=" + digest + "\n";
}
struct Fixture {
    fs::path root =
        fs::temp_directory_path() / ("isaac-lan-update-" + std::to_string(std::random_device{}()));
    fs::path game = root / "game [test]", source = root / "workshop";
    Fixture() {
        require(fs::create_directory(root), "reserve unique fixture");
        write(game / ".isaac-lan-install", "IsaacLAN/1\n");
        write(game / payloadFile, "installed DLL");
        write(game / "isaac-lan/session.keep", "saved session");
        write(game / "isaac-lan/installation.json", "installation ownership unchanged");
    }
    ~Fixture() {
        std::error_code error;
        fs::remove_all(root, error);
    }
    void package(const std::string& version = "0.6.4", const std::string& bytes = "new") {
        write(source / manifestFile, manifest(version, bytes));
        write(source / payloadFile, bytes);
    }
    Selection select(std::string_view baseline = "0.6.3", FileHash hasher = hash) {
        auto selection = isaac::updates::select(game, source, baseline, gameBuild, hasher);
        require(read(game / payloadFile) == "installed DLL", "root DLL remains unchanged");
        require(read(game / "isaac-lan/session.keep") == "saved session", "session preserved");
        require(read(game / "isaac-lan/installation.json") == "installation ownership unchanged",
                "installer ownership remains unchanged");
        require(selection.candidates.back() == game / payloadFile, "root is last fallback");
        return selection;
    }
};
void manifests() {
    require(parseManifest(manifest()).has_value(), "valid manifest");
    std::string crlf;
    for (auto c : manifest()) {
        if (c == '\n')
            crlf += '\r';
        crlf += c;
    }
    require(parseManifest(crlf).has_value(), "CRLF manifest");
    require(*parseVersion("0.6.10") > *parseVersion("0.6.9"), "numeric version ordering");
    for (const auto* version :
         {"", "1.2", "1.2.3.4", "1.2.-3", "01.2.3", "1.2.3/../4", "4294967296.0.0", "1.2.3-beta"})
        require(!parseVersion(version), "invalid version rejected");
    const auto valid = manifest();
    for (const auto& invalid : {valid + "unexpected\n", valid.substr(0, valid.size() - 1),
                                std::string(maxManifestBytes + 1, 'x'), manifest("../../escape"),
                                manifest("0.6.4", "new", "../game")})
        require(!parseManifest(invalid), "invalid manifest rejected");
    for (std::size_t length = 0; length < valid.size(); ++length)
        require(!parseManifest(std::string_view(valid).substr(0, length)),
                "all truncations rejected");
}
void selection() {
    Fixture fixture;
    require(fixture.select().candidates.size() == 1, "missing workshop uses baseline");
    fixture.package();
    const auto first = fixture.select();
    require(first.candidates.size() == 2 && read(first.candidates.front()) == "new",
            "complete source is copied and selected");
    require(first.candidates.front().parent_path() != fixture.source, "load a private cache copy");
    const auto modified = fs::last_write_time(first.candidates.front());
    require(fixture.select().candidates == first.candidates, "repeat selection is stable");
    require(fs::last_write_time(first.candidates.front()) == modified, "cache is not rewritten");
    fs::remove_all(fixture.source);
    require(fixture.select().candidates == first.candidates, "cached update works offline");
    require(fixture.select("0.6.5").candidates.size() == 1, "manual upgrade wins over old cache");
    fixture.package("0.6.10", "next");
    require(read(fixture.select().candidates.front()) == "next", "higher version selected");
    fixture.package("0.6.9");
    require(read(fixture.select().candidates.front()) == "next", "workshop cannot downgrade cache");
}
void recovery() {
    Fixture fixture;
    fixture.package();
    const auto prior = fixture.select().candidates.front();
    fixture.package("0.6.5", "next");
    write(fixture.source / payloadFile, "partial download");
    require(fixture.select().candidates.front() == prior, "partial update retains prior cache");
    for (const auto& entry : fs::directory_iterator(fixture.game / "isaac-lan/versions"))
        require(!entry.path().filename().string().starts_with(".staging-"), "failed stage cleaned");
    fixture.package("0.6.5", "next");
    const auto current = fixture.select().candidates.front();
    write(current, "corrupted cache");
    require(fixture.select().candidates.front() == prior,
            "corrupt cache falls back to prior version");
    write(prior, "also corrupt");
    require(fixture.select().candidates.size() == 1, "all damaged caches fall back to baseline");
    fixture.package("0.6.6");
    auto changedSource = +[](const fs::path& path) -> std::string {
        if (path.parent_path().filename().string().starts_with(".staging-"))
            throw std::runtime_error("injected hash failure");
        return hash(path);
    };
    require(fixture.select("0.6.3", changedSource).candidates.size() == 1,
            "hash failure never commits or hides root fallback");
    fixture.package("0.6.7", "next");
    sourceToChange = fixture.source;
    auto changingManifest = +[](const fs::path& path) -> std::string {
        if (path.parent_path().filename().string().starts_with(".staging-"))
            write(sourceToChange / manifestFile, manifest("0.6.8", "next"));
        return hash(path);
    };
    require(fixture.select("0.6.3", changingManifest).candidates.size() == 1,
            "a source manifest changed during copying cannot be committed");
}
void boundaries() {
    Fixture fixture;
    fixture.package();
    for (const auto& invalid : {manifest("0.6.4", "new", "1.9.7.16.J459"),
                                manifest("0.6.4", "new", gameBuild, loaderABI + 1),
                                manifest("0.6.2"), manifest("0.6.3"), std::string("broken")}) {
        write(fixture.source / manifestFile, invalid);
        require(fixture.select().candidates.size() == 1, "unsupported source skipped");
    }
    fixture.package();
    fs::remove(fixture.game / ".isaac-lan-install");
    require(fixture.select().candidates.size() == 1, "uninstalled copies never auto-enable");
    write(fixture.game / ".isaac-lan-install", "IsaacLAN/1\n");
    const auto cache = fixture.game / "isaac-lan/versions";
    write(cache, "foreign path");
    require(fixture.select().candidates.size() == 1, "foreign cache path preserved");
    require(read(cache) == "foreign path", "foreign path not replaced");
#ifndef _WIN32
    fs::remove(cache);
    fs::create_directory(fixture.root / "foreign");
    fs::create_directory_symlink(fixture.root / "foreign", cache);
    require(fixture.select().candidates.size() == 1, "cache symlink rejected");
    require(fs::is_empty(fixture.root / "foreign"), "no writes through cache symlink");
#endif
}
} // namespace
int main(int argc, char** argv) {
    try {
        const std::string name = argc == 2 ? argv[1] : "";
        if (name == "manifests")
            manifests();
        else if (name == "selection")
            selection();
        else if (name == "recovery")
            recovery();
        else if (name == "boundaries")
            boundaries();
        else
            throw std::runtime_error("unknown update test");
        std::cout << "PASS extension update " << name << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

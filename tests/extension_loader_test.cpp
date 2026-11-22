#include "app/extension_loader.h"
#include "core/extension_package.h"
#include "supported_game_versions.h"
#include <algorithm>
#include <vector>
#include "runtime/extension_update.h"
#include "runtime/extension_files.h"
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <random>
#include <stdexcept>

namespace {
namespace fs = std::filesystem;
using namespace isaac::updates;
void require(bool value, const char* detail) {
    if (!value)
        throw std::runtime_error(detail);
}
void write(const fs::path& path, const std::string& value) {
    fs::create_directories(path.parent_path());
    std::ofstream(path, std::ios::binary) << value;
}
constexpr auto plus = &isaac::engine::supportedGameVersions[0];
void prepare(const fs::path& directory, const fs::path& fixture, const std::string& version,
             const isaac::engine::GameVersion& target = *plus, bool publishMarker = false) {
    fs::create_directories(directory);
    // Publish fresh source files, as Steam does; production only copies into a
    // newly reserved staging directory and never overwrites a source DLL.
    fs::remove(directory / payloadFile);
    fs::copy_file(fixture, directory / payloadFile);
    const auto fields = "\nversion=" + version + "\ngame_build=" + std::string(target.version) +
                        "\nloader_abi=" + std::to_string(loaderABI) +
                        "\nsha256=" + isaac::updates::fileHash(directory / payloadFile) + "\n";
    write(directory / manifestFile, manifestMagic + fields);
    if (publishMarker)
        write(directory / buildManifestFile,
              buildManifestMagic + fields + "backend=" + std::string(target.backend) +
                  "\nversion_rva=" + std::to_string(target.markerRva) + "\n");
}
std::vector<char> gameImage(const isaac::engine::GameVersion& version) {
    const auto marker = std::string(version.version) + "-";
    std::vector<char> image(version.markerRva + marker.size());
    std::copy(marker.begin(), marker.end(), image.begin() + version.markerRva);
    return image;
}
isaac::loader::Extension loadVersion(const fs::path& game,
                                     const isaac::engine::GameVersion& version = *plus) {
    const auto image = gameImage(version);
    return isaac::loader::load(game, "0.6.3", image.data(), image.size());
}
fs::path load(const fs::path& game, const isaac::engine::GameVersion* version = plus) {
    const auto loaded = loadVersion(game, *version);
    require(loaded.module && loaded.bootstrap, "load extension and bootstrap export");
    using ModulePath = const wchar_t*(__cdecl*)();
    const auto proc = GetProcAddress(loaded.module, "IsaacLanTestModulePath");
    ModulePath path{};
    std::memcpy(&path, &proc, sizeof(proc));
    require(path != nullptr, "fixture path export");
    const fs::path result = path();
    require(loaded.bootstrap(nullptr) == 0, "synthetic bootstrap completes without game code");
    FreeLibrary(loaded.module);
    return result;
}
struct Temporary {
    fs::path root =
        fs::temp_directory_path() / ("isaac-lan-loader-" + std::to_string(std::random_device{}()));
    Temporary() {
        require(fs::create_directory(root), "reserve unique loader fixture");
    }
    ~Temporary() {
        std::error_code error;
        fs::remove_all(root, error);
    }
};
void workshopGamePatches(const fs::path& root, const fs::path& compatible,
                         const fs::path& incompatible) {
    const auto game = root / "steamapps/common/Game";
    const auto source =
        root / "steamapps/workshop/content" / workshopApp / workshopItem / workshopDirectory;
    const auto cache = game / "isaac-lan/versions";
    const isaac::engine::GameVersion nextPlus{"repentance_plus", "1.9.7.21.J987", 0x180};
    const isaac::engine::GameVersion nextBase{"repentance", "1.7.9b.J986", 0x240};
    const auto plusDir = source / nextPlus.backend;
    const auto baseDir = source / nextBase.backend;
    write(game / ".isaac-lan-install", "IsaacLAN/1\n");
    for (const auto& version : isaac::engine::supportedGameVersions) {
        const auto installed = game / "isaac-lan/backends" / version.backend;
        fs::create_directories(installed);
        fs::copy_file(compatible, installed / payloadFile);
    }
    fs::copy_file(compatible, game / payloadFile);
    auto unsupported = [&](const isaac::engine::GameVersion& version) {
        const auto loaded = loadVersion(game, version);
        require(!loaded.module && loaded.failure.code == isaac::startup::Code::gameCompatibility,
                "unrecognized image must never run an old installed DLL");
    };
    prepare(plusDir, compatible, "0.6.4", nextPlus);
    unsupported(nextPlus); // Legacy metadata cannot identify a new executable.
    prepare(baseDir, compatible, "0.6.4", nextPlus, true);
    unsupported(nextPlus); // A marker must come from its own edition.
    prepare(plusDir, compatible, "0.6.3", nextPlus, true);
    unsupported(nextPlus); // Installed baseline still applies.
    prepare(plusDir, compatible, "0.6.4", nextPlus, true);
    write(plusDir / payloadFile, "partial");
    unsupported(nextPlus);
    require(!fs::exists(cache) || fs::is_empty(cache),
            "incomplete download cannot commit an update");
    const isaac::engine::GameVersion suffix{nextPlus.backend, "9.7.21.J987",
                                            nextPlus.markerRva + 2};
    prepare(plusDir, compatible, "0.6.4", suffix, true);
    unsupported(nextPlus);
    prepare(plusDir, compatible, "0.6.4", nextPlus, true);
    auto moved = nextPlus;
    ++moved.markerRva;
    unsupported(moved);
    auto changed = nextPlus;
    changed.version = "1.9.7.21.J988";
    unsupported(changed);
    prepare(baseDir, compatible, "0.6.5", nextBase, true);
    auto ambiguous = gameImage(nextBase);
    auto first = gameImage(nextPlus);
    std::copy(first.begin(), first.end(), ambiguous.begin());
    require(isaac::loader::load(game, "0.6.3", ambiguous.data(), ambiguous.size()).failure.code ==
                isaac::startup::Code::gameCompatibility,
            "two intact matching editions are ambiguous");
    require(!fs::exists(cache) || fs::is_empty(cache), "ambiguous packages never enter the cache");
    write(baseDir / payloadFile, "interrupted transfer");
    const auto intact = isaac::loader::load(game, "0.6.3", ambiguous.data(), ambiguous.size());
    require(intact.module, "a damaged second source cannot hide the one complete match");
    FreeLibrary(intact.module);
    prepare(baseDir, compatible, "0.6.5", nextBase, true);
    const auto update = load(game, &nextPlus);
    const auto vanilla = load(game, &nextBase);
    require(update.parent_path().parent_path() == cache &&
                vanilla.parent_path().parent_path() == cache && update != vanilla,
            "both new game builds use their own private cached updates");
    prepare(plusDir, incompatible, "0.6.6", nextPlus, true);
    require(load(game, &nextPlus) == update,
            "a bad ABI export falls back within the same game build");
    fs::remove_all(source);
    require(load(game, &nextPlus) == update && load(game, &nextBase) == vanilla,
            "each future game build restarts from its own cache with Steam offline");
    unsupported(changed);
    fs::remove(game / ".isaac-lan-install");
    unsupported(nextPlus);
}
} // namespace
int wmain(int argc, wchar_t** argv) {
    // Deliberately invalid DLLs must return a load error instead of opening a
    // Windows "Bad Image" dialog and blocking this unattended fixture.
    SetErrorMode(GetErrorMode() | SEM_FAILCRITICALERRORS);
    try {
        require(argc == 5, "expected compatible, incompatible, failing and missing-export DLLs");
        wchar_t executable[32768]{};
        require(GetModuleFileNameW(nullptr, executable, std::size(executable)) != 0,
                "locate fixture build directory");
        const auto binaryDirectory = fs::path(executable).parent_path();
        // Cross-compiled CTest arguments may still use the Linux build prefix.
        const auto compatible = binaryDirectory / fs::path(argv[1]).filename();
        const auto incompatible = binaryDirectory / fs::path(argv[2]).filename();
        const auto failing = binaryDirectory / fs::path(argv[3]).filename();
        const auto missingExport = binaryDirectory / fs::path(argv[4]).filename();
        Temporary temporary;
        workshopGamePatches(temporary.root / "updates", compatible, incompatible);
        const auto missing = temporary.root / L"缺失.dll";
        auto rejected = isaac::loader::loadInstalled(missing);
        require(!rejected.module && !rejected.bootstrap &&
                    rejected.failure.code == isaac::startup::Code::extensionLoad &&
                    rejected.failure.path == missing.wstring() && rejected.failure.systemError,
                "Missing DLL lost its failure stage, Unicode path or OS error");
        rejected = isaac::loader::loadInstalled(missingExport);
        require(!rejected.module && !rejected.bootstrap &&
                    rejected.failure.code == isaac::startup::Code::bootstrapExport &&
                    rejected.failure.systemError.value() == ERROR_PROC_NOT_FOUND,
                "Missing bootstrap export was misreported as a load failure");
        require(GetModuleHandleW(missingExport.filename().c_str()) == nullptr,
                "Rejected DLL was not unloaded");
        auto diagnostic = isaac::loader::loadInstalled(failing);
        require(diagnostic.bootstrap != nullptr, "Load diagnostic fixture");
        const auto status = diagnostic.bootstrap(nullptr);
        const auto message = isaac::loader::failureMessage(diagnostic, status);
        require(status == 29 && message.find(L"C:\\文档\\startup.log") != message.npos &&
                    message.find(L"system:5") != message.npos,
                "Loader did not use the payload's detailed failure export");
        FreeLibrary(diagnostic.module);
        diagnostic = isaac::loader::loadInstalled(compatible);
        const auto legacy = isaac::loader::failureMessage(diagnostic, 14);
        require(legacy.find(L"code 14") != legacy.npos && legacy.find(L"目录") != legacy.npos &&
                    legacy.find(L"游戏版本") == legacy.npos,
                "Legacy payload without an error export lost directory-specific guidance");
        require(isaac::loader::failureMessage(diagnostic, 0).empty(),
                "Successful bootstrap produced an error message");
        const auto unknown = isaac::loader::failureMessage(diagnostic, 4001);
        require(unknown.find(L"4001") != unknown.npos && unknown.find(L"UNKNOWN") != unknown.npos,
                "Unknown payload code was lost");
        FreeLibrary(diagnostic.module);
        write(temporary.root / "hash-vector", "abc");
        require(isaac::updates::fileHash(temporary.root / "hash-vector") ==
                    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "SHA-256 matches independent standard vector");
        const auto game = temporary.root / L"steamapps/common/Game [\u6d4b\u8bd5]";
        const auto source = temporary.root / "steamapps/workshop/content" / workshopApp /
                            workshopItem / workshopDirectory;
        write(game / ".isaac-lan-install", "IsaacLAN/1\n");
        write(game / "isaac-lan/session.keep", "preserved session");
        fs::copy_file(compatible, game / payloadFile);
        require(load(game) == game / payloadFile, "no package uses installed root");
        require(plus->backend == "repentance_plus", "legacy fixture uses the Repentance+ build");
        const auto split = temporary.root / "split";
        std::vector<char> image;
        for (const auto& expected : isaac::engine::supportedGameVersions) {
            const auto marker = std::string(expected.version) + "-";
            image.assign(expected.markerRva + marker.size(), 0);
            std::copy(marker.begin(), marker.end(), image.begin() + expected.markerRva);
            auto version = isaac::engine::identifyGame(image.data(), image.size()).installed;
            require(version == &expected, "identify the running game's exact version marker");
            const auto body = split / "isaac-lan/backends" / version->backend / payloadFile;
            fs::create_directories(body.parent_path());
            fs::copy_file(compatible, body);
            require(load(split, version) == body,
                    "one installation routes each game to its own DLL");
            require(!isaac::engine::identifyGame(image.data(), image.size() - 1).installed,
                    "reject truncated version marker");
            image.back() = 'X';
            require(!isaac::engine::identifyGame(image.data(), image.size()).installed,
                    "reject changed marker delimiter");
        }
        image.clear();
        for (const auto& candidate : isaac::engine::supportedGameVersions) {
            const auto marker = std::string(candidate.version) + "-";
            image.resize(std::max(image.size(), candidate.markerRva + marker.size()), 0);
            std::copy(marker.begin(), marker.end(), image.begin() + candidate.markerRva);
        }
        require(isaac::engine::identifyGame(image.data(), image.size()).ambiguous,
                "ambiguous markers cannot choose a backend");
        require(!isaac::loader::load(split, "0.6.3", image.data(), image.size()).module,
                "unknown game cannot load a baseline");
        fs::remove(split / "isaac-lan/backends" / plus->backend / payloadFile);
        fs::copy_file(compatible, split / payloadFile);
        require(!loadVersion(split).module, "missing backend cannot adopt a leftover root DLL");
        prepare(source, compatible, "0.6.4");
        auto active = load(game);
        require(active != game / payloadFile &&
                    active.parent_path().parent_path() == game / "isaac-lan/versions",
                "raw Workshop source is adopted before any mods refresh");
        require(isaac::updates::fileHash(active) == isaac::updates::fileHash(compatible),
                "BCrypt verifies exact cached bytes");
        const auto held = loadVersion(game);
        require(held.module != nullptr, "hold an existing session DLL open");
        prepare(source, compatible, "0.6.5");
        const auto newer = load(game);
        require(newer != active && fs::exists(active), "a loaded prior version is never replaced");
        FreeLibrary(held.module);
        active = newer;
        // Metadata alone cannot authorize a DLL with a different loader contract.
        prepare(source, incompatible, "0.6.6");
        require(load(game) == active, "incompatible DLL export falls back to prior valid version");
        prepare(source, compatible, "0.6.7");
        const auto locked = CreateFileW((source / payloadFile).c_str(), GENERIC_READ, 0, nullptr,
                                        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        require(locked != INVALID_HANDLE_VALUE, "lock source to simulate an update in progress");
        const auto duringDownload = load(game);
        CloseHandle(locked);
        require(duringDownload == active, "unreadable source preserves the previous version");
        write(temporary.root / "invalid DLL", "not a PE image");
        prepare(source, temporary.root / "invalid DLL", "0.6.8");
        require(load(game) == active, "LoadLibrary failure preserves the previous version");
        fs::remove_all(source);
        require(load(game) == active, "cache loads without Steam files or a Steam API context");
        fs::remove(game / ".isaac-lan-install");
        require(load(game) == game / payloadFile, "cache does not enable an uninstalled copy");
        // A marked test launch must load the exact root fixture it was given.
        const auto lab = temporary.root / "lab";
        const auto labGame = lab / "game";
        write(lab / ".isaac-lan-lab", "owned fixture");
        write(labGame / ".isaac-lan-install", "IsaacLAN/1\n");
        write(labGame / "isaac-lan/session.keep", "preserved fixture");
        fs::copy_file(compatible, labGame / payloadFile);
        prepare(source, compatible, "0.6.4");
        isaac::updates::select(labGame, source, "0.6.3", {plus->backend, plus->version},
                               isaac::updates::fileHash);
        wchar_t previous[32768]{};
        GetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", previous, std::size(previous));
        SetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", lab.c_str());
        const auto isolated = load(labGame);
        SetEnvironmentVariableW(L"ISAAC_LAN_LAB_ROOT", *previous ? previous : nullptr);
        require(isolated == labGame / payloadFile, "isolated fixture bypasses automatic updates");
        std::cout << "PASS native extension loading, ABI fallback, actual module path and lab "
                     "isolation\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

#include "runtime/extension_update.h"
#include "core/extension_package.h"
#include <algorithm>
#include <fstream>
#include <random>
#include <stdexcept>

namespace isaac::updates {
namespace {
namespace fs = std::filesystem;
bool directory(const fs::path& path) {
    const auto status = fs::symlink_status(path);
    return fs::is_directory(status) && !fs::is_symlink(status);
}
bool regular(const fs::path& path, std::uintmax_t limit) {
    const auto status = fs::symlink_status(path);
    return fs::is_regular_file(status) && fs::file_size(path) <= limit;
}
std::string read(const fs::path& path) {
    if (!regular(path, maxManifestBytes))
        throw std::runtime_error("Invalid update manifest file");
    std::ifstream input(path, std::ios::binary);
    std::array<char, maxManifestBytes + 1> bytes{};
    input.read(bytes.data(), bytes.size());
    const auto size = static_cast<std::size_t>(input.gcount());
    if (!input.eof() || size > maxManifestBytes)
        throw std::runtime_error("Cannot read update manifest");
    return {bytes.data(), size};
}
bool verified(const fs::path& path, const Package& package, FileHash hash) {
    return regular(path, maxPayloadBytes) && hash(path) == package.sha256;
}
struct Staging {
    fs::path path;
    ~Staging() {
        // Only remove this transaction's fixed files. Unexpected contents are
        // retained instead of recursively deleting paths we did not create.
        std::error_code error;
        fs::remove(path / manifestFile, error);
        fs::remove(path / payloadFile, error);
        fs::remove(path, error);
    }
};
} // namespace

Selection select(const fs::path& game, const fs::path& workshop, std::string_view baselineVersion,
                 std::string_view gameBuild, FileHash hash) {
    Selection result;
    const auto baseline = parseVersion(baselineVersion);
    const auto fallback = game / payloadFile;
    try {
        if (!baseline || read(game / ".isaac-lan-install") != "IsaacLAN/1\n")
            throw std::runtime_error("Automatic updates require an installed extension");
        const auto data = game / "isaac-lan";
        const auto cache = data / "versions";
        if (!directory(data))
            throw std::runtime_error("Invalid extension data directory");
        if (fs::exists(cache) && !directory(cache))
            throw std::runtime_error("Invalid extension version directory");
        auto eligible = [&](const Package& package) {
            return package.abi == loaderABI && package.gameBuild == gameBuild &&
                   *parseVersion(package.version) > *baseline;
        };
        std::vector<std::pair<Package, fs::path>> packages;
        if (directory(cache))
            for (const auto& entry : fs::directory_iterator(cache)) {
                try {
                    if (!directory(entry.path()))
                        continue;
                    const auto package = parseManifest(read(entry.path() / manifestFile));
                    if (package && eligible(*package) &&
                        entry.path().filename() == package->directory())
                        packages.emplace_back(*package, entry.path());
                } catch (const std::exception&) {
                    // An interrupted or damaged cache entry cannot hide others.
                }
            }
        try {
            if (!workshop.empty() && directory(workshop)) {
                const auto sourceManifest = read(workshop / manifestFile);
                const auto package = parseManifest(sourceManifest);
                if (!package || !eligible(*package))
                    throw std::runtime_error("Workshop update is incompatible or not newer");
                const auto destination = cache / package->directory();
                if (!directory(destination)) {
                    fs::create_directory(cache);
                    // Never overwrite an existing cache path, including damaged
                    // or foreign files. Concurrent launches may stage separately.
                    const auto temporary =
                        cache / (".staging-" + std::to_string(std::random_device{}()));
                    if (!fs::create_directory(temporary))
                        throw std::runtime_error("Cannot reserve update staging directory");
                    Staging staging{temporary};
                    if (!regular(workshop / payloadFile, maxPayloadBytes))
                        throw std::runtime_error("Invalid Workshop update DLL");
                    fs::copy_file(workshop / payloadFile, temporary / payloadFile);
                    if (!verified(temporary / payloadFile, *package, hash) ||
                        read(workshop / manifestFile) != sourceManifest)
                        throw std::runtime_error("Workshop update is incomplete or changed");
                    std::ofstream output(temporary / manifestFile, std::ios::binary);
                    output << sourceManifest;
                    output.close();
                    if (!output)
                        throw std::runtime_error("Cannot write staged update manifest");
                    fs::rename(temporary, destination);
                }
                const auto cached = parseManifest(read(destination / manifestFile));
                if (!cached || cached->sha256 != package->sha256 ||
                    cached->version != package->version || !eligible(*cached))
                    throw std::runtime_error("Cached update does not match Workshop package");
                packages.insert(packages.begin(), {*package, destination});
            }
        } catch (const std::exception& error) {
            result.detail = error.what();
        }
        std::stable_sort(packages.begin(), packages.end(), [](const auto& left, const auto& right) {
            return *parseVersion(left.first.version) > *parseVersion(right.first.version);
        });
        for (const auto& [package, path] : packages) {
            try {
                const auto dll = path / payloadFile;
                if (verified(dll, package, hash) &&
                    std::find(result.candidates.begin(), result.candidates.end(), dll) ==
                        result.candidates.end())
                    result.candidates.push_back(dll);
            } catch (const std::exception&) {
                // Retain earlier complete packages when one version is damaged.
            }
        }
    } catch (const std::exception& error) {
        result.detail = error.what();
    }
    result.candidates.push_back(fallback);
    return result;
}
} // namespace isaac::updates

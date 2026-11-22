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
    std::error_code error;
    return fs::is_directory(fs::symlink_status(path, error));
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
struct Candidate {
    Package package;
    fs::path directory, sourceManifest;
    std::string manifest;
};

fs::path stage(const Candidate& candidate, const fs::path& cache, FileHash hash) {
    const auto& package = candidate.package;
    const auto destination = cache / package.directory();
    if (!directory(destination)) {
        fs::create_directory(cache);
        const auto temporary = cache / (".staging-" + std::to_string(std::random_device{}()));
        if (!fs::create_directory(temporary))
            throw std::runtime_error("Cannot reserve update staging directory");
        Staging staging{temporary};
        if (!regular(candidate.directory / payloadFile, maxPayloadBytes))
            throw std::runtime_error("Invalid Workshop update DLL");
        fs::copy_file(candidate.directory / payloadFile, temporary / payloadFile);
        if (!verified(temporary / payloadFile, package, hash) ||
            read(candidate.sourceManifest) != candidate.manifest)
            throw std::runtime_error("Workshop update is incomplete or changed");
        std::ofstream output(temporary / manifestFile, std::ios::binary);
        output << candidate.manifest;
        output.close();
        if (!output)
            throw std::runtime_error("Cannot write staged update manifest");
        std::error_code error;
        fs::rename(temporary, destination, error);
        // A concurrent launch may have committed the same immutable package.
        if (error && !directory(destination))
            throw std::system_error(error);
    }
    if (parseManifest(read(destination / manifestFile)) != package)
        throw std::runtime_error("Cached update does not match Workshop package");
    return destination;
}

bool conflictingBuilds(const std::vector<Candidate>& candidates) {
    return !candidates.empty() &&
           std::any_of(candidates.begin() + 1, candidates.end(), [&](const Candidate& candidate) {
               const auto& first = candidates.front().package;
               const auto& next = candidate.package;
               return next.backend != first.backend || next.gameBuild != first.gameBuild ||
                      next.markerRva != first.markerRva;
           });
}
} // namespace

bool GameTarget::accepts(const Package& package) const {
    if (!build.empty() && build != package.gameBuild)
        return false;
    if (!package.markerRva)
        return !build.empty();
    if (!backend.empty() && backend != package.backend)
        return false;
    return matchesMarker ? matchesMarker(package.gameBuild, package.markerRva) : !build.empty();
}

Selection select(const fs::path& game, const fs::path& workshop, std::string_view baselineVersion,
                 const GameTarget& target, FileHash hash, const fs::path& installed) {
    Selection result;
    try {
        const auto baseline = parseVersion(baselineVersion);
        if (!baseline || read(game / ".isaac-lan-install") != "IsaacLAN/1\n")
            throw std::runtime_error("Automatic updates require an installed extension");
        const auto data = game / "isaac-lan";
        const auto cache = data / "versions";
        if (!directory(data) || (fs::exists(cache) && !directory(cache)))
            throw std::runtime_error("Invalid extension update directory");

        std::vector<Candidate> candidates;
        auto consider = [&](const fs::path& path, bool download, std::string_view edition = {}) {
            try {
                if (!directory(path))
                    return;
                auto file = path / manifestFile;
                if (download && !edition.empty() &&
                    fs::symlink_status(path / buildManifestFile).type() != fs::file_type::not_found)
                    file = path / buildManifestFile;
                auto raw = read(file);
                auto package = parseManifest(raw);
                if (!package || package->abi != loaderABI ||
                    *parseVersion(package->version) <= *baseline)
                    return;
                if (download) {
                    if ((file.filename() == buildManifestFile) != (package->markerRva != 0) ||
                        (package->markerRva && package->backend != edition))
                        return;
                } else if (path.filename() != package->directory())
                    return;
                if (!target.accepts(*package))
                    return;
                candidates.push_back(
                    {std::move(*package), path, download ? file : fs::path{}, std::move(raw)});
            } catch (const std::exception& error) {
                result.detail = error.what();
            }
        };
        if (!workshop.empty() && directory(workshop)) {
            if (target.build.empty()) {
                for (const auto edition : editions)
                    consider(workshop / edition, true, edition);
            } else if (validGameBuild(target.build)) {
                auto source = workshop / target.backend;
                if (directory(source))
                    consider(source, true, target.backend);
                else {
                    const auto legacy = workshop / target.build;
                    consider(directory(legacy) ? legacy : workshop, true);
                }
            }
        }
        if (directory(cache)) {
            for (const auto& entry : fs::directory_iterator(cache))
                consider(entry.path(), false);
        }
        // A partial download cannot create an ambiguity or hide a complete cached build.
        if (target.build.empty() && conflictingBuilds(candidates)) {
            std::erase_if(candidates, [&](const Candidate& candidate) {
                try {
                    return !verified(candidate.directory / payloadFile, candidate.package, hash);
                } catch (const std::exception&) {
                    return true;
                }
            });
            if (conflictingBuilds(candidates))
                throw std::runtime_error("Game matches multiple update build markers");
        }
        std::stable_sort(candidates.begin(), candidates.end(),
                         [](const Candidate& left, const Candidate& right) {
                             return *parseVersion(left.package.version) >
                                    *parseVersion(right.package.version);
                         });
        for (const auto& candidate : candidates) {
            try {
                const auto path = candidate.sourceManifest.empty() ? candidate.directory
                                                                   : stage(candidate, cache, hash);
                const auto dll = path / payloadFile;
                if (std::find(result.candidates.begin(), result.candidates.end(), dll) ==
                        result.candidates.end() &&
                    verified(dll, candidate.package, hash)) {
                    result.candidates.push_back(dll);
                    if (!result.newest)
                        result.newest = candidate.package;
                }
            } catch (const std::exception& error) {
                result.detail = error.what();
            }
        }
    } catch (const std::exception& error) {
        result.detail = error.what();
    }
    if (!target.build.empty() && !installed.empty())
        result.candidates.push_back(installed);
    return result;
}
std::optional<Package> pending(const fs::path& game, const fs::path& workshop,
                               std::string_view runningVersion, std::string_view backend,
                               std::string_view gameBuild, FileHash hash) {
    return select(game, workshop, runningVersion, {backend, gameBuild}, hash).newest;
}
} // namespace isaac::updates

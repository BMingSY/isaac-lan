#include "app/bridge_manifest.h"
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <cstdio>

namespace {
void log(const std::string&) {}
void require(bool value, const char* message) {
    if (!value)
        throw std::runtime_error(message);
}
struct Directory {
    std::filesystem::path path = std::filesystem::temp_directory_path() /
                                 ("isaac-lan-manifest-" + std::to_string(GetCurrentProcessId()));
    Directory() {
        require(std::filesystem::create_directory(path), "Temporary path exists");
    }
    ~Directory() {
        std::error_code error;
        std::filesystem::remove_all(path, error);
    }
};
void write(const std::filesystem::path& path, const char* value) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream(path, std::ios::binary) << value;
}
} // namespace
int main() {
    try {
        Directory directory;
        write(directory.path / "isaac_lan_probe.dll", "extension");
        auto first = isaac::app::buildManifest(directory.path, "fixture.version", log);
        require(first.fingerprint ==
                    "778ee4385db41cdd9ff09237485c4cdc8f4470d4cd9e18931056c4eac33fbc61",
                "Build fingerprint framing changed");
        write(directory.path / "mods/a/main.lua", "mod");
        auto mod = isaac::app::buildManifest(directory.path, "fixture.version", log);
        require(mod.fingerprint == first.fingerprint && mod.mods != first.mods,
                "Advisory mods changed required build identity");
        write(directory.path / "mods/a/disable.it", "");
        auto disabled = isaac::app::buildManifest(directory.path, "fixture.version", log);
        require(disabled.mods == first.mods, "Disabled mod entered the manifest");
        require(isaac::app::buildManifest(directory.path, "other.version", log).fingerprint !=
                    first.fingerprint,
                "Different game builds share an identity");
        write(directory.path / "isaac_lan_probe.dll", "changed");
        require(isaac::app::buildManifest(directory.path, "fixture.version", log).fingerprint !=
                    first.fingerprint,
                "Different DLLs share an identity");
        std::filesystem::remove(directory.path / "isaac_lan_probe.dll");
        bool rejected = false;
        try {
            isaac::app::buildManifest(directory.path, "fixture.version", log);
        } catch (const std::exception&) {
            rejected = true;
        }
        require(rejected, "Missing build input was accepted");
        std::puts("PASS build identity, advisory mods and missing input");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

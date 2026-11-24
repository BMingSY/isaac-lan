#include "app/bridge_manifest.h"
#include "app/content_hash.h"
#include <algorithm>
#include <vector>

namespace isaac::app {
namespace {
// The workshop distribution registers an empty mod and carries installer files.
// Treat any other entry point or game asset as potentially observable content.
bool distributionOnly(const std::filesystem::path& root,
                      const std::vector<std::filesystem::path>& files) {
    bool registration = false;
    for (const auto& file : files) {
        const auto top = file.begin()->wstring();
        if (file == L"main.lua") {
            constexpr std::string_view entry = "RegisterMod(\"Isaac LAN Workshop Package\", 1)";
            if (std::filesystem::file_size(root / file) > entry.size() + 2)
                return false;
            std::ifstream script(root / file, std::ios::binary);
            std::string line;
            if (!std::getline(script, line))
                return false;
            if (line.ends_with('\r'))
                line.pop_back();
            if (line != entry || script.peek() != std::char_traits<char>::eof())
                return false;
            registration = true;
        } else if (file != L"metadata.xml" && file != L"preview.png" && file != L"安装说明.txt" &&
                   top != L"isaac-lan-update" && !top.starts_with(L"Isaac-LAN-v"))
            return false;
    }
    return registration;
}
} // namespace
BridgeManifest buildManifest(const std::filesystem::path& directory, std::string_view version,
                             void (*logger)(const std::string&),
                             const std::filesystem::path& extensionPath) {
    namespace fs = std::filesystem;
    BridgeManifest result;
    app::ContentHash hash;
    hash.text("Isaac LAN/build-v1");
    hash.text(std::string(version));
    ContentHash extension;
    extension.file(extensionPath.empty() ? directory / L"isaac_lan_probe.dll" : extensionPath);
    hash.text(extension.finish());
    result.fingerprint = hash.finish();
    // Mods are advisory, including unreadable files. They never enter the
    // required build identity used for joining or restoring a saved session.
    result.mods.clear();
    try {
        ContentHash mods;
        mods.text("Isaac LAN/mods-v2");
        std::vector<std::string> packages;
        std::size_t fileCount = 0;
        bool stock = true;
        if (fs::is_directory(directory / L"mods"))
            for (const auto& mod : fs::directory_iterator(directory / L"mods")) {
                if (!mod.is_directory() || fs::exists(mod.path() / L"disable.it"))
                    continue;
                std::vector<fs::path> files;
                for (const auto& item : fs::recursive_directory_iterator(mod.path()))
                    if (item.is_regular_file())
                        files.push_back(item.path().lexically_relative(mod.path()));
                std::sort(files.begin(), files.end());
                ContentHash package;
                for (const auto& file : files) {
                    const auto path = file.generic_u8string();
                    package.text(std::string(path.begin(), path.end()));
                    ContentHash entry;
                    entry.file(mod.path() / file);
                    package.text(entry.finish());
                }
                if (!files.empty()) {
                    packages.push_back(package.finish());
                    stock = stock && distributionOnly(mod.path(), files);
                }
                fileCount += files.size();
            }
        // The package includes its metadata and internal paths. Steam and local
        // installations may use different names for the enclosing directory.
        std::sort(packages.begin(), packages.end());
        for (const auto& package : packages)
            mods.text(package);
        logger("mod_manifest files=" + std::to_string(fileCount));
        result.mods = mods.finish();
        result.stockContent = stock;
    } catch (const std::exception& e) {
        logger("mod_manifest=UNKNOWN " + std::string(e.what()));
    }
    return result;
}
} // namespace isaac::app

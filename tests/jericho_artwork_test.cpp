#include "presentation/jericho_artwork.h"
#include "test_support.h"
#include <windows.h>
#include <fstream>
#include <string>

namespace {
std::string read(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(file), {}};
}
} // namespace
int main() {
    const auto root = std::filesystem::temp_directory_path() /
                      ("isaac-lan-jericho-artwork-" + std::to_string(GetCurrentProcessId()));
    std::filesystem::remove_all(root);
    const auto animation = isaac::presentation::prepareJerichoArtwork(root);
    const auto path = std::filesystem::path(std::u8string(animation.begin(), animation.end()));
    const auto png = path.parent_path() / "jericho.png";
    const auto original = read(png), descriptor = read(path);
    require(path.is_absolute() && path.parent_path().parent_path() == root / "cache/jericho",
            "Artwork escaped its owned cache");
    require(original.starts_with("\x89PNG\r\n\x1a\n") && !descriptor.empty(),
            "Embedded artwork was not extracted");
    const auto modified = std::filesystem::last_write_time(png);
    require(isaac::presentation::prepareJerichoArtwork(root) == animation &&
                std::filesystem::last_write_time(png) == modified,
            "Unchanged artwork was rewritten");
    { std::ofstream(png, std::ios::binary | std::ios::trunc) << "partial"; }
    { std::ofstream(path, std::ios::binary | std::ios::trunc) << "partial"; }
    isaac::presentation::prepareJerichoArtwork(root);
    require(read(png) == original && read(path) == descriptor,
            "Corrupted cache did not recover the embedded PNG and animation");
    for (const auto& entry : std::filesystem::directory_iterator(path.parent_path()))
        require(entry.path() == path || entry.path() == png, "Temporary artwork was left behind");
    std::filesystem::remove_all(root);
}

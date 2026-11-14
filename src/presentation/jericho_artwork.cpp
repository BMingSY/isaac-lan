#include "presentation/jericho_artwork.h"
#include "presentation/asset_cache.h"
#include "jericho_artwork_version.h"
#include <string_view>

namespace isaac::presentation {
namespace {
std::string_view resource(HMODULE module, const wchar_t* name) {
    const auto entry = FindResourceW(module, name, MAKEINTRESOURCEW(10));
    const auto loaded = entry ? LoadResource(module, entry) : nullptr;
    const auto bytes = loaded ? static_cast<const char*>(LockResource(loaded)) : nullptr;
    const auto size = entry ? SizeofResource(module, entry) : 0;
    if (!bytes || !size)
        throw std::runtime_error("jericho_artwork_resource");
    return {bytes, size};
}
void extract(const std::filesystem::path& path, std::string_view bytes) {
    std::ifstream file(path, std::ios::binary);
    if (file) {
        const std::string existing{std::istreambuf_iterator<char>(file), {}};
        if (existing == bytes)
            return;
    }
    file.close();
    cacheAsset(path, bytes.data(), bytes.size());
}
} // namespace
std::string prepareJerichoArtwork(const std::filesystem::path& configDirectory) {
    static constexpr wchar_t owner[] = L"Isaac LAN room artwork";
    HMODULE module = nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            owner, &module))
        throw std::runtime_error("jericho_artwork_module");
    const auto cache = configDirectory / "cache/jericho" / jerichoArtworkVersion;
    std::filesystem::create_directories(cache);
    extract(cache / "jericho.png", resource(module, L"ISAAC_LAN_JERICHO_PNG"));
    const auto path = cache / "jericho.anm2";
    extract(path, resource(module, L"ISAAC_LAN_JERICHO_ANM2"));
    const auto encoded = path.generic_u8string();
    return {encoded.begin(), encoded.end()};
}
} // namespace isaac::presentation

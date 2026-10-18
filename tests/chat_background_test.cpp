#include "presentation/chat_background.h"
#include "test_support.h"
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <array>
#include <fstream>
#include <utility>
#include <string>

namespace {
std::string read(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(file), {}};
}
constexpr CLSID pngEncoder = {
    0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
constexpr CLSID jpegEncoder = {
    0x557cf401, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
constexpr CLSID bmpEncoder = {
    0x557cf400, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
constexpr CLSID gifEncoder = {
    0x557cf402, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
constexpr CLSID tiffEncoder = {
    0x557cf405, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
struct Imaging {
    ULONG_PTR token = 0;
    Imaging() {
        Gdiplus::GdiplusStartupInput startup;
        require(Gdiplus::GdiplusStartup(&token, &startup, nullptr) == Gdiplus::Ok, "GDI startup");
    }
    ~Imaging() {
        Gdiplus::GdiplusShutdown(token);
    }
};
void saveCustom(const std::filesystem::path& path, const CLSID& encoder = pngEncoder,
                unsigned width = 3, unsigned height = 2) {
    Gdiplus::Bitmap bitmap(width, height, PixelFormat32bppARGB);
    bitmap.SetPixel(0, 0, Gdiplus::Color(0, 0, 0, 0));
    bitmap.SetPixel(1, 0, Gdiplus::Color(127, 80, 120, 160));
    bitmap.SetPixel(2, 0, Gdiplus::Color(255, 160, 80, 20));
    require(bitmap.Save(path.c_str(), &encoder, nullptr) == Gdiplus::Ok, "Fixture image write");
}
void checkCachedPixels(const std::filesystem::path& source, const std::filesystem::path& cache) {
    Gdiplus::Bitmap original(source.c_str()), converted(cache.c_str());
    GUID format{};
    require(converted.GetLastStatus() == Gdiplus::Ok &&
                converted.GetRawFormat(&format) == Gdiplus::Ok && format == Gdiplus::ImageFormatPNG,
            "Cache is not a decodable PNG");
    require(original.GetWidth() == converted.GetWidth() &&
                original.GetHeight() == converted.GetHeight(),
            "Conversion changed dimensions");
    for (unsigned y = 0; y < original.GetHeight(); ++y) {
        for (unsigned x = 0; x < original.GetWidth(); ++x) {
            Gdiplus::Color before, after;
            require(original.GetPixel(x, y, &before) == Gdiplus::Ok &&
                        converted.GetPixel(x, y, &after) == Gdiplus::Ok &&
                        before.GetValue() == after.GetValue(),
                    "Conversion changed decoded pixels or alpha");
        }
    }
}
} // namespace
int main() {
    Imaging imaging;
    using isaac::presentation::prepareChatBackground;
    const auto root = std::filesystem::temp_directory_path() /
                      (L"isaac-lan-chat-image-" + std::to_wstring(GetCurrentProcessId()));
    require(std::filesystem::create_directory(root), "Temporary directory is already in use");
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::filesystem::remove_all(path);
        }
    } cleanup{root};
    const auto base = prepareChatBackground(root, "");
    require(base.warning.empty() && base.width == 0 && base.height == 0 && base.animation.empty(),
            "Default background did not select a solid color");
    require(!std::filesystem::exists(root / "cache"), "Default background created image cache");
    const auto customName = std::filesystem::path(u8"背景 & custom.png");
    saveCustom(root / customName);
    const auto originalCustom = read(root / customName);
    const auto encoded = customName.generic_u8string();
    const auto custom = prepareChatBackground(root, {encoded.begin(), encoded.end()});
    require(custom.warning.empty() && custom.width == 3 && custom.height == 2,
            "Unicode relative custom image failed");
    require(read(root / "cache/chat/background.png") == originalCustom &&
                read(root / customName) == originalCustom,
            "PNG or its alpha was modified");
    checkCachedPixels(root / customName, root / "cache/chat/background.png");
    for (const auto& [name, encoder] :
         std::array{std::pair{"picture.jpg", jpegEncoder}, std::pair{"picture.jpeg", jpegEncoder},
                    std::pair{"jpeg-disguised-as.png", jpegEncoder},
                    std::pair{"no-extension", jpegEncoder}, std::pair{"picture.bmp", bmpEncoder}}) {
        saveCustom(root / name, encoder);
        const auto before = read(root / name);
        const auto converted = prepareChatBackground(root, name);
        require(converted.warning.empty() && converted.width == 3 && converted.height == 2 &&
                    !converted.animation.empty(),
                "Common image format did not load");
        checkCachedPixels(root / name, root / "cache/chat/background.png");
        require(read(root / name) == before, "Conversion modified the source image");
    }
    const auto cacheBeforeUnsupported = read(root / "cache/chat/background.png");
    for (const auto& [name, encoder] : std::array{std::pair{"unsupported.gif", gifEncoder},
                                                  std::pair{"gif-disguised-as.png", gifEncoder},
                                                  std::pair{"unsupported.tiff", tiffEncoder}}) {
        saveCustom(root / name, encoder);
        const auto unsupported = prepareChatBackground(root, name);
        require(!unsupported.warning.empty() && unsupported.animation.empty(),
                "Unsupported format accepted");
        require(read(root / "cache/chat/background.png") == cacheBeforeUnsupported,
                "Unsupported format replaced cache");
    }
    const auto absolute = (root / customName).generic_u8string();
    require(prepareChatBackground(root, {absolute.begin(), absolute.end()}).warning.empty(),
            "Absolute custom image failed");
    const auto cleared = prepareChatBackground(root, "");
    require(cleared.animation.empty() && cleared.warning.empty(),
            "Clearing the selection reused a stale cached image");
    const auto missing = prepareChatBackground(root, "missing.png");
    require(!missing.warning.empty() && missing.animation.empty() && missing.width == 0 &&
                missing.height == 0,
            "Missing custom image did not fall back to a solid color");
    { std::ofstream(root / "broken.png", std::ios::binary) << originalCustom.substr(0, 40); }
    const auto broken = prepareChatBackground(root, "broken.png");
    require(!broken.warning.empty() && broken.animation.empty(),
            "Corrupt PNG was passed to the game");
    saveCustom(root / "wide.jpg", jpegEncoder, 4097, 1);
    saveCustom(root / "many-pixels.png", pngEncoder, 3000, 3000);
    const auto cached = read(root / "cache/chat/background.png");
    for (const auto* name : {"wide.jpg", "many-pixels.png"}) {
        const auto oversized = prepareChatBackground(root, name);
        require(!oversized.warning.empty() && oversized.animation.empty(),
                "Oversized image accepted");
        require(read(root / "cache/chat/background.png") == cached,
                "Rejected image replaced cache");
    }
    for (const auto* name : {"empty.jpg", "fake.png", "truncated.jpg", "too-large.bmp"}) {
        {
            std::ofstream file(root / name, std::ios::binary);
            if (std::string_view(name) == "fake.png")
                file << "not an image";
            if (std::string_view(name) == "truncated.jpg")
                file << read(root / "picture.jpg").substr(0, 30);
            if (std::string_view(name) == "too-large.bmp") {
                file.seekp(16 * 1024 * 1024);
                file.put(0);
            }
        }
        const auto invalid = prepareChatBackground(root, name);
        require(!invalid.warning.empty() && invalid.animation.empty() && invalid.width == 0 &&
                    invalid.height == 0,
                "Invalid image did not select solid fallback");
        require(read(root / "cache/chat/background.png") == cached, "Invalid image replaced cache");
    }
    std::filesystem::create_directory(root / "blocked");
    std::ofstream(root / "blocked/cache") << "owned obstacle";
    const auto blocked =
        prepareChatBackground(root / "blocked", {absolute.begin(), absolute.end()});
    require(blocked.animation.empty() && !blocked.warning.empty(),
            "Cache failure did not return fallback");
    require(prepareChatBackground(root / "blocked", "").warning.empty(),
            "Solid background tried to access an unavailable image cache");
    const auto lockedCache = CreateFileW((root / "cache/chat/background.png").c_str(), GENERIC_READ,
                                         FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
    require(lockedCache != INVALID_HANDLE_VALUE, "Could not lock cache for replacement failure");
    const auto locked = prepareChatBackground(root, "picture.jpg");
    CloseHandle(lockedCache);
    require(locked.animation.empty() && !locked.warning.empty() &&
                read(root / "cache/chat/background.png") == cached,
            "Failed converted cache replacement damaged the previous image");
    for (const auto& entry : std::filesystem::directory_iterator(root / "cache/chat"))
        require(entry.path().extension() != ".tmp", "Staged image leaked after preparation");
    std::puts("PASS solid default, PNG/JPEG/BMP import, Unicode paths, pixels/alpha and "
              "cache fallback");
}

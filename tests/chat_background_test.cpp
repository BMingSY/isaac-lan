#include "presentation/chat_background.h"
#include "test_support.h"
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <fstream>
#include <string>

namespace {
std::string read(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(file), {}};
}
void saveCustom(const std::filesystem::path& path) {
    ULONG_PTR token = 0;
    Gdiplus::GdiplusStartupInput startup;
    require(Gdiplus::GdiplusStartup(&token, &startup, nullptr) == Gdiplus::Ok, "GDI startup");
    {
        Gdiplus::Bitmap bitmap(3, 2, PixelFormat32bppARGB);
        bitmap.SetPixel(0, 0, Gdiplus::Color(0, 0, 0, 0));
        bitmap.SetPixel(1, 0, Gdiplus::Color(127, 80, 120, 160));
        bitmap.SetPixel(2, 0, Gdiplus::Color(255, 160, 80, 20));
        const CLSID png = {
            0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
        require(bitmap.Save(path.c_str(), &png, nullptr) == Gdiplus::Ok, "Fixture PNG write");
    }
    Gdiplus::GdiplusShutdown(token);
}
} // namespace
int main() {
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
    require(base.warning.empty() && base.width > 0 && base.height > 0 && !base.animation.empty(),
            "Bundled background was not materialized");
    const auto original = read(root / "cache/chat/background.png");
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
    const auto absolute = (root / customName).generic_u8string();
    require(prepareChatBackground(root, {absolute.begin(), absolute.end()}).warning.empty(),
            "Absolute custom image failed");
    const auto missing = prepareChatBackground(root, "missing.png");
    require(!missing.warning.empty() && missing.width == base.width &&
                read(root / "cache/chat/background.png") == original,
            "Missing custom image did not fall back to bundled art");
    { std::ofstream(root / "broken.png", std::ios::binary) << originalCustom.substr(0, 40); }
    require(!prepareChatBackground(root, "broken.png").warning.empty() &&
                read(root / "cache/chat/background.png") == original,
            "Corrupt PNG was passed to the game");
    {
        auto oversized = originalCustom;
        oversized[16] = 1; // Reject an enormous IHDR before decoder allocation.
        std::ofstream(root / "oversized.png", std::ios::binary)
            .write(oversized.data(), oversized.size());
    }
    require(!prepareChatBackground(root, "oversized.png").warning.empty(),
            "Oversized image accepted");
    std::filesystem::create_directory(root / "blocked");
    std::ofstream(root / "blocked/cache") << "owned obstacle";
    const auto blocked = prepareChatBackground(root / "blocked", "");
    require(blocked.animation.empty() && !blocked.warning.empty(),
            "Cache failure did not return fallback");
    for (const auto& entry : std::filesystem::directory_iterator(root / "cache/chat"))
        require(entry.path().extension() != ".tmp", "Staged image leaked after preparation");
    std::puts(
        "PASS bundled/custom PNG, Unicode paths, alpha preservation, fallback and cache cleanup");
}

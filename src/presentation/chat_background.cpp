#include "presentation/chat_background.h"
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
#include <algorithm>
#include <array>
#include <cstring>
#include <fstream>
#include <span>
#include <stdexcept>
#include <vector>

namespace isaac::presentation {
namespace {
constexpr std::size_t maxImageBytes = 16 * 1024 * 1024;
constexpr unsigned maxImageEdge = 4096, maxImagePixels = 8 * 1024 * 1024;
struct Imaging {
    ULONG_PTR token = 0;
    Imaging() {
        Gdiplus::GdiplusStartupInput startup;
        if (Gdiplus::GdiplusStartup(&token, &startup, nullptr) != Gdiplus::Ok)
            throw std::runtime_error("image_decoder_startup");
    }
    ~Imaging() {
        Gdiplus::GdiplusShutdown(token);
    }
};
std::pair<unsigned, unsigned> dimensions(std::span<const unsigned char> bytes) {
    constexpr std::array<unsigned char, 8> signature{137, 80, 78, 71, 13, 10, 26, 10};
    if (bytes.size() < 33 || bytes.size() > maxImageBytes ||
        !std::equal(signature.begin(), signature.end(), bytes.begin()) ||
        std::memcmp(bytes.data() + 12, "IHDR", 4) != 0)
        throw std::runtime_error("invalid_png");
    auto integer = [&](std::size_t offset) {
        return (unsigned(bytes[offset]) << 24) | (unsigned(bytes[offset + 1]) << 16) |
               (unsigned(bytes[offset + 2]) << 8) | unsigned(bytes[offset + 3]);
    };
    const auto width = integer(16), height = integer(20);
    if (!width || !height || width > maxImageEdge || height > maxImageEdge ||
        width * height > maxImagePixels)
        throw std::runtime_error("image_dimensions");
    auto memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
    if (!memory)
        throw std::runtime_error("image_memory");
    const auto buffer = GlobalLock(memory);
    if (!buffer) {
        GlobalFree(memory);
        throw std::runtime_error("image_memory");
    }
    std::memcpy(buffer, bytes.data(), bytes.size());
    GlobalUnlock(memory);
    struct Stream {
        IStream* value = nullptr;
        ~Stream() {
            if (value)
                value->Release();
        }
    } stream;
    if (FAILED(CreateStreamOnHGlobal(memory, TRUE, &stream.value))) {
        GlobalFree(memory);
        throw std::runtime_error("image_stream");
    }
    Gdiplus::Bitmap bitmap(stream.value);
    if (bitmap.GetLastStatus() != Gdiplus::Ok || bitmap.GetWidth() != width ||
        bitmap.GetHeight() != height)
        throw std::runtime_error("image_decode");
    Gdiplus::BitmapData pixels{};
    Gdiplus::Rect area(0, 0, width, height);
    if (bitmap.LockBits(&area, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &pixels) !=
        Gdiplus::Ok)
        throw std::runtime_error("image_decode");
    bitmap.UnlockBits(&pixels);
    return {width, height};
}
std::vector<unsigned char> readImage(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    const auto size = file.tellg();
    if (!file || size < 0 || size > static_cast<std::streamoff>(maxImageBytes))
        throw std::runtime_error("image_file");
    std::vector<unsigned char> bytes(static_cast<std::size_t>(size));
    file.seekg(0);
    if (!file.read(reinterpret_cast<char*>(bytes.data()), bytes.size()))
        throw std::runtime_error("image_read");
    return bytes;
}
void write(const std::filesystem::path& path, const char* bytes, std::size_t size) {
    const auto temporary = path.wstring() + L"." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::error_code ignored;
            std::filesystem::remove(path, ignored);
        }
    } cleanup{temporary};
    std::ofstream file(cleanup.path, std::ios::binary | std::ios::trunc);
    if (!file.write(bytes, size) || !file.flush())
        throw std::runtime_error("image_cache_write");
    file.close();
    if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING))
        throw std::runtime_error("image_cache_replace");
}
std::string animation(unsigned width, unsigned height) {
    return "<AnimatedActor><Info CreatedBy=\"Isaac LAN\" Version=\"1\" Fps=\"30\"/>"
           "<Content><Spritesheets><Spritesheet Path=\"background.png\" Id=\"0\"/></Spritesheets>"
           "<Layers><Layer Name=\"Background\" Id=\"0\" SpritesheetId=\"0\"/></Layers>"
           "<Nulls/><Events/></Content><Animations DefaultAnimation=\"Idle\">"
           "<Animation Name=\"Idle\" FrameNum=\"1\" Loop=\"false\"><RootAnimation>"
           "<Frame XPosition=\"0\" YPosition=\"0\" XScale=\"100\" YScale=\"100\" Delay=\"1\" "
           "Visible=\"true\" RedTint=\"255\" GreenTint=\"255\" BlueTint=\"255\" AlphaTint=\"255\" "
           "RedOffset=\"0\" GreenOffset=\"0\" BlueOffset=\"0\" Rotation=\"0\" "
           "Interpolated=\"false\"/>"
           "</RootAnimation><LayerAnimations><LayerAnimation LayerId=\"0\" Visible=\"true\">"
           "<Frame XPosition=\"0\" YPosition=\"0\" XPivot=\"0\" YPivot=\"0\" XCrop=\"0\" "
           "YCrop=\"0\" "
           "Width=\"" +
           std::to_string(width) + "\" Height=\"" + std::to_string(height) +
           "\" "
           "XScale=\"100\" YScale=\"100\" Delay=\"1\" Visible=\"true\" RedTint=\"255\" "
           "GreenTint=\"255\" "
           "BlueTint=\"255\" AlphaTint=\"255\" RedOffset=\"0\" GreenOffset=\"0\" BlueOffset=\"0\" "
           "Rotation=\"0\" Interpolated=\"false\"/></LayerAnimation></LayerAnimations>"
           "<NullAnimations/><Triggers/></Animation></Animations></AnimatedActor>";
}
} // namespace
ChatBackground prepareChatBackground(const std::filesystem::path& configDirectory,
                                     const std::string& selectedImage) {
    ChatBackground result;
    if (selectedImage.empty())
        return result;
    try {
        Imaging imaging;
        const std::u8string selectedPath(selectedImage.begin(), selectedImage.end());
        const auto bytes = readImage(configDirectory / std::filesystem::path(selectedPath));
        const auto [width, height] = dimensions(bytes);
        const auto cache = configDirectory / L"cache/chat";
        std::filesystem::create_directories(cache);
        write(cache / L"background.png", reinterpret_cast<const char*>(bytes.data()), bytes.size());
        const auto descriptor = animation(width, height);
        const auto path = cache / L"background.anm2";
        write(path, descriptor.data(), descriptor.size());
        const auto encoded = path.generic_u8string();
        result.animation.assign(encoded.begin(), encoded.end());
        result.width = width;
        result.height = height;
    } catch (const std::exception& error) {
        result.warning = std::string("background_unavailable=") + error.what();
    }
    return result;
}
} // namespace isaac::presentation

#include "presentation/chat_background.h"
#include <windows.h>
#include <objidl.h>
#include <gdiplus.h>
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
template <typename Writer>
void write(const std::filesystem::path& path, const Writer& writeContent) {
    const auto temporary = path.wstring() + L"." + std::to_wstring(GetCurrentProcessId()) + L".tmp";
    struct Cleanup {
        std::filesystem::path path;
        ~Cleanup() {
            std::error_code ignored;
            std::filesystem::remove(path, ignored);
        }
    } cleanup{temporary};
    writeContent(cleanup.path);
    if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING))
        throw std::runtime_error("image_cache_replace");
}
void write(const std::filesystem::path& path, const char* bytes, std::size_t size) {
    write(path, [&](const auto& temporary) {
        std::ofstream file(temporary, std::ios::binary | std::ios::trunc);
        if (!file.write(bytes, size) || !file.flush())
            throw std::runtime_error("image_cache_write");
    });
}
std::pair<unsigned, unsigned> prepareImage(std::span<const unsigned char> bytes,
                                           const std::filesystem::path& path) {
    if (bytes.empty())
        throw std::runtime_error("image_decode");
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
    if (bitmap.GetLastStatus() != Gdiplus::Ok)
        throw std::runtime_error("image_decode");
    GUID format{};
    if (bitmap.GetRawFormat(&format) != Gdiplus::Ok ||
        (format != Gdiplus::ImageFormatPNG && format != Gdiplus::ImageFormatJPEG &&
         format != Gdiplus::ImageFormatBMP))
        throw std::runtime_error("image_format");
    const auto width = bitmap.GetWidth(), height = bitmap.GetHeight();
    if (!width || !height || width > maxImageEdge || height > maxImageEdge ||
        width * height > maxImagePixels)
        throw std::runtime_error("image_dimensions");
    // Force pixel decoding before publishing the cache, including unchanged PNGs.
    Gdiplus::BitmapData pixels{};
    Gdiplus::Rect area(0, 0, width, height);
    if (bitmap.LockBits(&area, Gdiplus::ImageLockModeRead, PixelFormat32bppARGB, &pixels) !=
        Gdiplus::Ok)
        throw std::runtime_error("image_decode");
    bitmap.UnlockBits(&pixels);
    std::filesystem::create_directories(path.parent_path());
    if (format == Gdiplus::ImageFormatPNG) {
        write(path, reinterpret_cast<const char*>(bytes.data()), bytes.size());
    } else {
        // A single PNG frame keeps the existing game Sprite path and opacity rules.
        constexpr CLSID pngEncoder = {
            0x557cf406, 0x1a04, 0x11d3, {0x9a, 0x73, 0x00, 0x00, 0xf8, 0x1e, 0xf3, 0x2e}};
        write(path, [&](const auto& temporary) {
            if (bitmap.Save(temporary.c_str(), &pngEncoder, nullptr) != Gdiplus::Ok)
                throw std::runtime_error("image_cache_encode");
        });
    }
    return {width, height};
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
        const auto cache = configDirectory / L"cache/chat";
        const auto [width, height] = prepareImage(bytes, cache / L"background.png");
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

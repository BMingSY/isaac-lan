#include "net/compression.h"
#include "net/protocol.h"
#include "core/deflate.h"
#include "core/zstd.h"
#include <windows.h>
#include <cstring>
#include <string>

namespace isaac::lan {
namespace {
constexpr std::size_t headerSize = 5;
} // namespace
struct StateCompression::Impl {
    compression::Zstd zstd;
    HMODULE module = nullptr;
    HANDLE compressor = nullptr, decompressor = nullptr;
    using Create = BOOL(WINAPI*)(DWORD, void*, HANDLE*);
    using Close = BOOL(WINAPI*)(HANDLE);
    using Transform = BOOL(WINAPI*)(HANDLE, LPCVOID, SIZE_T, PVOID, SIZE_T, PSIZE_T);
    Create createCompressor = nullptr, createDecompressor = nullptr;
    Close closeCompressor = nullptr, closeDecompressor = nullptr;
    Transform compress = nullptr, decompress = nullptr;
    template <class T> void bind(T& target, const char* name) {
        const auto proc = GetProcAddress(module, name);
        static_assert(sizeof(target) == sizeof(proc));
        std::memcpy(&target, &proc, sizeof(proc));
        if (!target)
            throw std::runtime_error("Windows Compression API unavailable");
    }
    void initialize() {
        if (compressor && decompressor)
            return;
        wchar_t system[MAX_PATH]{};
        if (!GetSystemDirectoryW(system, MAX_PATH))
            throw std::runtime_error("Cannot locate Windows compression library");
        module = LoadLibraryW((std::wstring(system) + L"\\cabinet.dll").c_str());
        if (!module)
            throw std::runtime_error("Cannot load Windows compression library");
        bind(createCompressor, "CreateCompressor");
        bind(createDecompressor, "CreateDecompressor");
        bind(closeCompressor, "CloseCompressor");
        bind(closeDecompressor, "CloseDecompressor");
        bind(compress, "Compress");
        bind(decompress, "Decompress");
        // COMPRESS_ALGORITHM_XPRESS_HUFF, buffer mode (no raw flag).
        if (!createCompressor(4, nullptr, &compressor) ||
            !createDecompressor(4, nullptr, &decompressor))
            throw std::runtime_error("Cannot initialize state compression");
    }
    ~Impl() {
        if (compressor && closeCompressor)
            closeCompressor(compressor);
        if (decompressor && closeDecompressor)
            closeDecompressor(decompressor);
        if (module)
            FreeLibrary(module);
    }
};
StateCompression::StateCompression() : impl(std::make_unique<Impl>()) {}
StateCompression::~StateCompression() = default;
std::vector<std::uint8_t> StateCompression::compress(std::span<const std::uint8_t> bytes,
                                                     std::span<const std::uint8_t> baseline) {
    if (bytes.empty() || bytes.size() > maxWorldSize || baseline.size() > maxWorldSize)
        throw std::runtime_error("Invalid state compression size");
    const auto compressed = impl->zstd.compress(bytes, maxWorldSize, baseline);
    const bool packed = compressed.size() < bytes.size();
    const auto payload = packed ? std::span<const std::uint8_t>(compressed) : bytes;
    std::vector<std::uint8_t> result(payload.size() + headerSize);
    result[0] = packed ? (baseline.empty() ? Mode::zstd : Mode::zstdPrefix) : Mode::raw;
    for (unsigned i = 0; i < 4; ++i)
        result[1 + i] = static_cast<std::uint8_t>(bytes.size() >> (24 - i * 8));
    std::memcpy(result.data() + headerSize, payload.data(), payload.size());
    return result;
}
std::vector<std::uint8_t> StateCompression::expand(std::span<const std::uint8_t> bytes,
                                                   std::span<const std::uint8_t> baseline) {
    Reader reader(bytes);
    const auto mode = reader.u8();
    const auto size = reader.u32();
    if (mode > Mode::zstdPrefix || !size || size > maxWorldSize || bytes.size() <= headerSize ||
        bytes.size() > maxWorldSize + headerSize || baseline.size() > maxWorldSize ||
        (mode == Mode::zstdPrefix && baseline.empty()) ||
        (mode != Mode::zstdPrefix && mode != Mode::raw && !baseline.empty()))
        throw std::runtime_error("Invalid compressed state header");
    if (mode == Mode::zstd || mode == Mode::zstdPrefix)
        return impl->zstd.expand(bytes.subspan(headerSize), size, maxWorldSize, baseline);
    if (mode == Mode::raw) {
        if (bytes.size() - headerSize != size)
            throw std::runtime_error("Invalid plain state size");
        return {bytes.begin() + headerSize, bytes.end()};
    }
    if (mode == Mode::deflate)
        return compression::inflate(bytes.subspan(headerSize), size, maxWorldSize);
    impl->initialize();
    std::vector<std::uint8_t> result(size);
    SIZE_T written = 0;
    if (!impl->decompress(impl->decompressor, bytes.data() + headerSize, bytes.size() - headerSize,
                          result.data(), result.size(), &written) ||
        written != size)
        throw std::runtime_error("Invalid compressed world state");
    return result;
}
} // namespace isaac::lan

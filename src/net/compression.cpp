#include "net/compression.h"
#include "net/protocol.h"
#include <windows.h>
#include <cstring>
#include <string>

namespace isaac::lan {
struct StateCompression::Impl {
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
std::vector<std::uint8_t> StateCompression::compress(std::span<const std::uint8_t> bytes) {
    if (bytes.empty() || bytes.size() > maxWorldSize)
        throw std::runtime_error("Invalid state compression size");
    impl->initialize();
    std::vector<std::uint8_t> result(bytes.size() + 5);
    result[0] = 0;
    for (unsigned i = 0; i < 4; ++i)
        result[1 + i] = static_cast<std::uint8_t>(bytes.size() >> (24 - i * 8));
    SIZE_T written = 0;
    if (impl->compress(impl->compressor, bytes.data(), bytes.size(), result.data() + 5,
                       bytes.size(), &written) &&
        written < bytes.size()) {
        result[0] = 1;
        result.resize(written + 5);
    } else
        std::memcpy(result.data() + 5, bytes.data(), bytes.size());
    return result;
}
std::vector<std::uint8_t> StateCompression::expand(std::span<const std::uint8_t> bytes) {
    Reader reader(bytes);
    const auto mode = reader.u8();
    const auto size = reader.u32();
    if (mode > 1 || !size || size > maxWorldSize || bytes.size() < 6)
        throw std::runtime_error("Invalid compressed state header");
    if (!mode) {
        if (bytes.size() - 5 != size)
            throw std::runtime_error("Invalid plain state size");
        return {bytes.begin() + 5, bytes.end()};
    }
    impl->initialize();
    std::vector<std::uint8_t> result(size);
    SIZE_T written = 0;
    if (!impl->decompress(impl->decompressor, bytes.data() + 5, bytes.size() - 5, result.data(),
                          result.size(), &written) ||
        written != size)
        throw std::runtime_error("Invalid compressed world state");
    return result;
}
} // namespace isaac::lan

#include "core/zstd.h"
#define ZSTD_STATIC_LINKING_ONLY
#include <zstd.h>
#include <algorithm>
#include <bit>
#include <stdexcept>

namespace isaac::compression {
namespace {
constexpr int compressionLevel = -1;
constexpr int prefixHashLog = 18;
constexpr std::size_t indexedPrefixThreshold = 64 * 1024;
void checked(std::size_t status) {
    if (ZSTD_isError(status))
        throw std::runtime_error(ZSTD_getErrorName(status));
}
void bounds(std::size_t size, std::size_t limit, std::size_t prefix) {
    if (!size || size > limit || prefix > limit || limit > ZSTD_MAX_INPUT_SIZE)
        throw std::runtime_error("Invalid Zstd state size");
}
} // namespace
struct Zstd::Impl {
    ZSTD_CCtx* encoder = ZSTD_createCCtx();
    ZSTD_DCtx* decoder = ZSTD_createDCtx();
    ~Impl() {
        ZSTD_freeCCtx(encoder);
        ZSTD_freeDCtx(decoder);
    }
};
Zstd::Zstd() : impl(std::make_unique<Impl>()) {
    if (!impl->encoder || !impl->decoder)
        throw std::runtime_error("Cannot allocate Zstd contexts");
}
Zstd::~Zstd() = default;
std::vector<std::uint8_t> Zstd::compress(std::span<const std::uint8_t> value, std::size_t limit,
                                         std::span<const std::uint8_t> prefix) {
    bounds(value.size(), limit, prefix.size());
    std::vector<std::uint8_t> result(ZSTD_compressBound(value.size()));
    auto* context = impl->encoder;
    checked(ZSTD_CCtx_reset(context, ZSTD_reset_session_and_parameters));
    checked(ZSTD_CCtx_setParameter(context, ZSTD_c_compressionLevel, compressionLevel));
    checked(ZSTD_CCtx_setParameter(context, ZSTD_c_windowLog,
                                   std::max<int>(10, std::bit_width(limit - 1))));
    checked(ZSTD_CCtx_setParameter(context, ZSTD_c_checksumFlag, 1));
    // The fast preset's small hash table loses most matches in a large world
    // prefix. Bound the index at 1 MiB and retain the small-state preset.
    if (prefix.size() >= indexedPrefixThreshold)
        checked(ZSTD_CCtx_setParameter(context, ZSTD_c_hashLog, prefixHashLog));
    checked(ZSTD_CCtx_refPrefix(context, prefix.data(), prefix.size()));
    const auto size =
        ZSTD_compress2(context, result.data(), result.size(), value.data(), value.size());
    const auto cleared = ZSTD_CCtx_refPrefix(context, nullptr, 0);
    checked(size);
    checked(cleared);
    result.resize(size);
    return result;
}
std::vector<std::uint8_t> Zstd::expand(std::span<const std::uint8_t> frame, std::size_t size,
                                       std::size_t limit, std::span<const std::uint8_t> prefix) {
    bounds(size, limit, prefix.size());
    if (frame.empty() || frame.size() > ZSTD_compressBound(limit))
        throw std::runtime_error("Invalid Zstd frame size");
    ZSTD_frameHeader header{};
    const auto status = ZSTD_getFrameHeader(&header, frame.data(), frame.size());
    checked(status);
    if (status || header.frameType != ZSTD_frame || header.frameContentSize != size ||
        header.windowSize > limit || header.dictID || !header.checksumFlag ||
        ZSTD_findFrameCompressedSize(frame.data(), frame.size()) != frame.size())
        throw std::runtime_error("Invalid bounded Zstd frame");
    std::vector<std::uint8_t> result(size);
    auto* context = impl->decoder;
    checked(ZSTD_DCtx_reset(context, ZSTD_reset_session_and_parameters));
    checked(ZSTD_DCtx_refPrefix(context, prefix.data(), prefix.size()));
    const auto written =
        ZSTD_decompressDCtx(context, result.data(), result.size(), frame.data(), frame.size());
    const auto cleared = ZSTD_DCtx_refPrefix(context, nullptr, 0);
    checked(written);
    checked(cleared);
    if (written != size)
        throw std::runtime_error("Zstd state length mismatch");
    return result;
}
std::size_t Zstd::memory() const {
    return ZSTD_sizeof_CCtx(impl->encoder) + ZSTD_sizeof_DCtx(impl->decoder);
}
} // namespace isaac::compression

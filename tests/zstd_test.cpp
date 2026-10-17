#include "core/zstd.h"
#include "test_support.h"
#include <zstd.h>
#include <random>

using Bytes = std::vector<std::uint8_t>;
constexpr std::size_t limit = 2 * 1024 * 1024;

void roundTrip() {
    isaac::compression::Zstd codec;
    std::mt19937 random(73);
    for (const auto size : {1u, 63u, 1024u, 140000u, 2097152u}) {
        Bytes value(size);
        for (auto& byte : value)
            byte = random();
        const auto packed = codec.compress(value, limit);
        require(codec.expand(packed, size, limit) == value, "Zstd round trip changed state");
        Bytes independent(size);
        require(ZSTD_decompress(independent.data(), size, packed.data(), packed.size()) == size &&
                    independent == value,
                "Frame is not interoperable Zstandard");
    }
}
void prefixes() {
    isaac::compression::Zstd codec;
    std::mt19937 random(91);
    Bytes base(140000);
    for (auto& byte : base)
        byte = random();
    auto value = base;
    value.insert(value.begin() + 1000, 913, 42);
    value.erase(value.begin() + 7000, value.begin() + 8013);
    value[200] ^= 12;
    const auto frame = codec.compress(value, limit, base);
    require(frame.size() < value.size() / 10, "Confirmed prefix did not reduce sparse state");
    require(codec.expand(frame, value.size(), limit, base) == value, "Prefix changed state");
    rejects([&] { codec.expand(frame, value.size(), limit); }, "Missing prefix was accepted");
    auto wrong = base;
    wrong[100000] ^= 1;
    rejects([&] { codec.expand(frame, value.size(), limit, wrong); }, "Wrong prefix was accepted");
    auto* independent = ZSTD_createDCtx();
    require(independent != nullptr, "Cannot allocate independent decoder");
    ZSTD_DCtx_refPrefix(independent, base.data(), base.size());
    Bytes output(value.size());
    const auto size =
        ZSTD_decompressDCtx(independent, output.data(), output.size(), frame.data(), frame.size());
    ZSTD_freeDCtx(independent);
    require(size == value.size() && output == value, "Prefix frame interoperability failed");
    // Reusing contexts after an error/full frame must not retain the preceding peer's dictionary.
    for (unsigned i = 0; i < 100; ++i) {
        const auto full = codec.compress(value, limit);
        require(codec.expand(full, value.size(), limit) == value,
                "A stale prefix leaked between views");
        const auto next = codec.compress(value, limit, base);
        require(codec.expand(next, value.size(), limit, base) == value,
                "Context reuse changed prefix state");
    }
    require(codec.memory() < 16 * limit, "Compression context memory is unbounded");
}
void bounds() {
    isaac::compression::Zstd codec;
    Bytes value(4096, 42);
    const auto frame = codec.compress(value, limit);
    rejects([&] { codec.compress({}, limit); }, "Empty state accepted");
    rejects([&] { codec.compress(value, value.size() - 1); }, "Oversized state accepted");
    rejects([&] { codec.compress(value, limit, Bytes(limit + 1)); }, "Oversized prefix accepted");
    rejects([&] { codec.expand(frame, value.size() + 1, limit); },
            "Wrong declared length accepted");
    rejects([&] { codec.expand(frame, value.size(), value.size() - 1); }, "Output exceeded limit");
    for (std::size_t n = 0; n < frame.size(); ++n)
        rejects([&] { codec.expand(std::span(frame).first(n), value.size(), limit); },
                "Truncated frame accepted");
    auto invalid = frame;
    invalid.back() ^= 1;
    rejects([&] { codec.expand(invalid, value.size(), limit); }, "Corrupt checksum accepted");
    invalid = frame;
    invalid.push_back(0);
    rejects([&] { codec.expand(invalid, value.size(), limit); }, "Trailing frame data accepted");
    invalid = frame;
    invalid.insert(invalid.end(), frame.begin(), frame.end());
    rejects([&] { codec.expand(invalid, value.size(), limit); }, "Concatenated frames accepted");
    require(codec.expand(frame, value.size(), limit) == value, "Rejected input poisoned decoder");
    // A valid generic Zstd frame is still invalid for this wire contract when
    // its checksum or known output length is omitted.
    auto* context = ZSTD_createCCtx();
    require(context != nullptr, "Cannot allocate independent encoder");
    for (bool knownSize : {false, true}) {
        ZSTD_CCtx_reset(context, ZSTD_reset_session_and_parameters);
        ZSTD_CCtx_setParameter(context, ZSTD_c_contentSizeFlag, knownSize);
        ZSTD_CCtx_setParameter(context, ZSTD_c_checksumFlag, !knownSize);
        Bytes generic(ZSTD_compressBound(value.size()));
        const auto length =
            ZSTD_compress2(context, generic.data(), generic.size(), value.data(), value.size());
        require(!ZSTD_isError(length), "Cannot create independent frame");
        generic.resize(length);
        rejects([&] { codec.expand(generic, value.size(), limit); },
                "Incomplete frame contract accepted");
    }
    ZSTD_freeCCtx(context);
}
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"round-trip", roundTrip}, {"prefixes", prefixes}, {"bounds", bounds}});
}

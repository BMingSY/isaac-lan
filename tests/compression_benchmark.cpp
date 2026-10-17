#include "core/deflate.h"
#include "core/snapshot_delta.h"
#include "core/zstd.h"
#include <lz4.h>
#include <algorithm>
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>
#include <numeric>
#include <string>

namespace {
using Bytes = std::vector<std::uint8_t>;
using Clock = std::chrono::steady_clock;
constexpr std::size_t limit = isaac::core::SnapshotDelta::limit;
constexpr unsigned warmup = 5;
struct View {
    Bytes base, value;
};
struct Packet {
    Bytes bytes;
    std::size_t expanded = 0;
    bool delta = false;
};
Bytes read(const char* name) {
    std::ifstream stream(name, std::ios::binary);
    Bytes result{std::istreambuf_iterator<char>(stream), {}};
    if (result.empty() || result.size() > limit)
        throw std::runtime_error("Snapshot is missing, empty or oversized");
    return result;
}
void stats(std::vector<double> values) {
    std::sort(values.begin(), values.end());
    std::cout << "{\"mean_ms\":"
              << std::accumulate(values.begin(), values.end(), 0.0) / values.size()
              << ",\"p95_ms\":" << values[(values.size() * 95 + 99) / 100 - 1]
              << ",\"p99_ms\":" << values[(values.size() * 99 + 99) / 100 - 1] << "}";
}
template <class Encode, class Decode>
void measure(const char* algorithm, unsigned peers, const std::vector<View>& views,
             unsigned iterations, Encode encode, Decode decode) {
    std::vector<double> enc, dec;
    std::size_t raw = 0, packed = 0;
    for (unsigned i = 0; i < iterations + warmup; ++i) {
        std::array<Packet, 3> packets;
        std::array<Bytes, 3> restored;
        const auto start = Clock::now();
        for (unsigned peer = 0; peer < peers; ++peer)
            packets[peer] = encode(views[peer % views.size()]);
        const auto middle = Clock::now();
        for (unsigned peer = 0; peer < peers; ++peer)
            restored[peer] = decode(packets[peer], views[peer % views.size()]);
        const auto end = Clock::now();
        raw = packed = 0;
        for (unsigned peer = 0; peer < peers; ++peer) {
            const auto& view = views[peer % views.size()];
            if (restored[peer] != view.value)
                throw std::runtime_error("Compression changed snapshot bytes");
            raw += view.value.size();
            packed += packets[peer].bytes.size();
        }
        if (i >= warmup) {
            enc.push_back(std::chrono::duration<double, std::milli>(middle - start).count());
            dec.push_back(std::chrono::duration<double, std::milli>(end - middle).count());
        }
    }
    std::cout << "{\"algorithm\":\"" << algorithm << "\",\"players\":" << peers + 1
              << ",\"views\":" << std::min<std::size_t>(peers, views.size())
              << ",\"samples\":" << iterations << ",\"raw_bytes\":" << raw
              << ",\"packed_bytes\":" << packed << ",\"encode\":";
    stats(enc);
    std::cout << ",\"decode\":";
    stats(dec);
    std::cout << "}" << std::endl;
}
} // namespace
int main(int argc, char** argv) {
    try {
        if (argc < 4 || argc > 8 || argc % 2 != 0)
            throw std::runtime_error("Usage: benchmark iterations base next [base next ...]");
        const auto iterations = std::stoul(argv[1]);
        if (iterations < 5 || iterations > 10000)
            throw std::runtime_error("Iterations must be 5..10000");
        std::vector<View> views;
        for (int i = 2; i < argc; i += 2)
            views.push_back({read(argv[i]), read(argv[i + 1])});
        isaac::compression::Zstd zstd;
        for (unsigned peers = 1; peers <= 3; ++peers) {
            measure(
                "miniz-full", peers, views, iterations,
                [](const View& v) {
                    return Packet{isaac::compression::deflate(v.value, limit), v.value.size()};
                },
                [](const Packet& p, const View&) {
                    return isaac::compression::inflate(p.bytes, p.expanded, limit);
                });
            measure(
                "lz4-full", peers, views, iterations,
                [](const View& v) {
                    Bytes out(LZ4_compressBound(static_cast<int>(v.value.size())));
                    const auto size = LZ4_compress_default(
                        reinterpret_cast<const char*>(v.value.data()),
                        reinterpret_cast<char*>(out.data()), static_cast<int>(v.value.size()),
                        static_cast<int>(out.size()));
                    if (size <= 0)
                        throw std::runtime_error("LZ4 encoding failed");
                    out.resize(size);
                    return Packet{std::move(out), v.value.size()};
                },
                [](const Packet& p, const View&) {
                    Bytes out(p.expanded);
                    if (LZ4_decompress_safe(
                            reinterpret_cast<const char*>(p.bytes.data()),
                            reinterpret_cast<char*>(out.data()), static_cast<int>(p.bytes.size()),
                            static_cast<int>(out.size())) != static_cast<int>(out.size()))
                        throw std::runtime_error("LZ4 decoding failed");
                    return out;
                });
            measure(
                "zstd-full", peers, views, iterations,
                [&](const View& v) {
                    return Packet{zstd.compress(v.value, limit), v.value.size()};
                },
                [&](const Packet& p, const View&) {
                    return zstd.expand(p.bytes, p.expanded, limit);
                });
            // Include the full-frame fallback candidate and baseline indexing in
            // both end-to-end send paths, as the production sender does.
            measure(
                "miniz-delta", peers, views, iterations,
                [](const View& v) {
                    Packet result{isaac::compression::deflate(v.value, limit), v.value.size()};
                    if (const auto delta = isaac::core::SnapshotDelta::encode(v.base, v.value)) {
                        auto packed = isaac::compression::deflate(*delta, limit);
                        if (packed.size() < result.bytes.size())
                            result = {std::move(packed), delta->size(), true};
                    }
                    return result;
                },
                [](const Packet& p, const View& v) {
                    auto out = isaac::compression::inflate(p.bytes, p.expanded, limit);
                    return p.delta ? isaac::core::SnapshotDelta::apply(v.base, out) : out;
                });
            measure(
                "zstd-prefix", peers, views, iterations,
                [&](const View& v) {
                    Packet result{zstd.compress(v.value, limit), v.value.size()};
                    auto prefix = zstd.compress(v.value, limit, v.base);
                    if (prefix.size() < result.bytes.size())
                        result = {std::move(prefix), v.value.size(), true};
                    return result;
                },
                [&](const Packet& p, const View& v) {
                    return zstd.expand(p.bytes, p.expanded, limit,
                                       p.delta ? std::span(v.base)
                                               : std::span<const std::uint8_t>{});
                });
        }
        std::cerr << "zstd_context_bytes=" << zstd.memory() << '\n';
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

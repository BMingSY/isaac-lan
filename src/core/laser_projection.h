#pragma once
#include "core/laser_state.h"
#include <algorithm>

// A standalone render path. Every scalar, endpoint and sample count is retained.
// Only the interior of a verified smooth, player-owned beam may be refined.
namespace isaac::presentation::laser_projection {
constexpr std::uint8_t projectedTag = 0xfe, exactTag = 0xfd;
constexpr unsigned anchors = 4;
constexpr double maxError = 1.0 / 32.0;
enum class Array : std::uint8_t { literal, cubic, differences, endpoints };
using Words = std::vector<std::uint32_t>;
using Output = lan::Writer;

inline unsigned knot(unsigned k, unsigned count) {
    return (k * (count - 1) + (anchors - 1) / 2) / (anchors - 1);
}
using Knots = std::array<std::array<float, 2>, anchors>;
inline std::array<float, 2> interpolate(const Knots& points, unsigned count, unsigned index) {
    std::array<double, 2> sum{};
    for (unsigned k = 0; k < anchors; ++k) {
        const int at = knot(k, count);
        if (static_cast<int>(index) == at)
            return points[k];
        double weight = 1;
        for (unsigned j = 0; j < anchors; ++j) {
            if (j == k)
                continue;
            const int other = knot(j, count);
            weight *= (static_cast<int>(index) - other) / static_cast<double>(at - other);
        }
        for (unsigned d = 0; d < 2; ++d)
            sum[d] += weight * points[k][d];
    }
    return {static_cast<float>(sum[0]), static_cast<float>(sum[1])};
}
inline bool fits(const Words& words, const Knots& points, bool& different) {
    const unsigned count = words.size() / 2;
    for (unsigned i = 0; i < count; ++i) {
        const auto reconstructed = interpolate(points, count, i);
        for (unsigned d = 0; d < 2; ++d)
            different |= std::bit_cast<std::uint32_t>(reconstructed[d]) != words[2 * i + d];
        const double dx =
            reconstructed[0] - static_cast<double>(std::bit_cast<float>(words[2 * i]));
        const double dy =
            reconstructed[1] - static_cast<double>(std::bit_cast<float>(words[2 * i + 1]));
        if (!(dx * dx + dy * dy <= maxError * maxError))
            return false;
    }
    return true;
}
inline void varint(Output& out, std::uint32_t value) {
    while (value >= 128) {
        out.u8(static_cast<std::uint8_t>(value) | 128);
        value >>= 7;
    }
    out.u8(value);
}
inline std::uint32_t varint(lan::Reader& in) {
    std::uint32_t result = 0;
    for (unsigned shift = 0; shift < 32; shift += 7) {
        const auto byte = in.u8();
        if (shift == 28 && byte > 15)
            break;
        result |= static_cast<std::uint32_t>(byte & 127) << shift;
        if (!(byte & 128))
            return result;
    }
    throw std::runtime_error("Invalid laser residual");
}
inline void scalars(Output& out, const LaserPath& path) {
    out.u8(path.sampleState);
    for (auto bits : path.values)
        out.u32(bits);
    out.u32(path.samples);
}
using Point = std::array<std::uint32_t, 2>;
// The short collision polyline and its dense drawing samples often share the
// native origin and endpoints. References are local to this one laser and tick.
struct Endpoints {
    std::array<Point, 4> values{};
    unsigned count = 2;
    unsigned index(Point point) const {
        for (unsigned i = 0; i < count; ++i)
            if (values[i] == point)
                return i;
        return values.size();
    }
    void write(Output& out, Point point) const {
        const auto i = index(point);
        out.u8(i);
        if (i == values.size()) {
            out.u32(point[0]);
            out.u32(point[1]);
        }
    }
    Point read(lan::Reader& in) const {
        const auto i = in.u8();
        if (i < count)
            return values[i];
        if (i == values.size())
            return {in.u32(), in.u32()};
        throw std::runtime_error("Invalid laser endpoint reference");
    }
};
constexpr double fractionScale = 16384.0;
using Fractions = std::array<std::int16_t, 2 * (anchors - 2)>;
inline std::array<float, 2> coordinate(Point p) {
    return {std::bit_cast<float>(p[0]), std::bit_cast<float>(p[1])};
}
inline Knots controlPoints(Point start, Point end, const Fractions& fractions) {
    Knots points{};
    points.front() = coordinate(start);
    points.back() = coordinate(end);
    const double dx = double(points.back()[0]) - points.front()[0];
    const double dy = double(points.back()[1]) - points.front()[1];
    for (unsigned k = 1; k + 1 < anchors; ++k) {
        const double u = fractions[2 * k - 2] / fractionScale,
                     v = fractions[2 * k - 1] / fractionScale;
        points[k] = {static_cast<float>(points.front()[0] + u * dx - v * dy),
                     static_cast<float>(points.front()[1] + u * dy + v * dx)};
    }
    return points;
}
inline bool fractionsFor(const Words& words, Point start, Point end, Fractions& fractions) {
    const auto first = coordinate(start), last = coordinate(end);
    const double dx = double(last[0]) - first[0], dy = double(last[1]) - first[1];
    const double length = dx * dx + dy * dy;
    if (length == 0)
        return false;
    for (unsigned k = 1; k + 1 < anchors; ++k) {
        const auto i = 2 * knot(k, words.size() / 2);
        const double x = double(std::bit_cast<float>(words[i])) - first[0];
        const double y = double(std::bit_cast<float>(words[i + 1])) - first[1];
        const std::array<double, 2> components{(x * dx + y * dy) / length,
                                               (y * dx - x * dy) / length};
        for (unsigned d = 0; d < 2; ++d) {
            const double value = std::round(components[d] * fractionScale);
            if (!(value >= INT16_MIN && value <= INT16_MAX))
                return false;
            fractions[2 * k - 2 + d] = static_cast<std::int16_t>(value);
        }
    }
    return true;
}
inline void writeArray(Output& out, const Words& words, const Endpoints& refs, bool allowCurve,
                       bool& refined) {
    const unsigned count = words.size() / 2;
    out.u16(count);
    if (count >= 2) {
        const Point start{words[0], words[1]}, end{words[2 * count - 2], words[2 * count - 1]};
        if (count == 2 && (refs.index(start) < refs.count || refs.index(end) < refs.count)) {
            out.u8(static_cast<unsigned>(Array::endpoints));
            refs.write(out, start);
            refs.write(out, end);
            return;
        }
        Fractions fractions;
        bool different = false;
        if (allowCurve && count > anchors && fractionsFor(words, start, end, fractions) &&
            fits(words, controlPoints(start, end, fractions), different)) {
            out.u8(static_cast<unsigned>(Array::cubic));
            refs.write(out, start);
            refs.write(out, end);
            for (auto value : fractions)
                out.u16(static_cast<std::uint16_t>(value));
            refined |= different;
            return;
        }
    }
    const auto mark = out.bytes.size();
    if (count > 2) {
        out.u8(static_cast<unsigned>(Array::differences));
        for (unsigned i = 0; i < 4; ++i)
            out.u32(words[i]);
        for (unsigned i = 4; i < words.size(); ++i) {
            const auto residual = words[i] - (2u * words[i - 2] - words[i - 4]);
            varint(out, (residual << 1) ^ (0u - (residual >> 31)));
        }
        if (out.bytes.size() - mark < 1 + words.size() * sizeof(std::uint32_t))
            return;
        out.bytes.resize(mark);
    }
    out.u8(static_cast<unsigned>(Array::literal));
    for (auto v : words)
        out.u32(v);
}
inline bool project(std::span<const std::uint8_t> raw, Output& out, bool playerBeam,
                    Point& endpoint) {
    lan::Reader reader(raw);
    const auto path = readLaserPath(reader);
    endpoint = {path.values[2], path.values[3]};
    out.bytes.clear();
    out.u8(projectedTag);
    scalars(out, path);
    bool refined = false;
    Endpoints refs;
    refs.values[0] = {path.values[0], path.values[1]};
    refs.values[1] = {path.values[2], path.values[3]};
    for (const auto& words : path.paths) {
        writeArray(out, words, refs, playerBeam, refined);
        if (!words.empty()) {
            refs.values[2] = {words[0], words[1]};
            refs.values[3] = {words[words.size() - 2], words.back()};
            refs.count = 4;
        }
    }
    if (out.bytes.size() >= raw.size()) {
        out.bytes.assign(raw.begin(), raw.end());
        return false;
    }
    out.bytes.front() = refined ? projectedTag : exactTag;
    return refined;
}
inline void expand(std::span<const std::uint8_t> bytes, Output& out, Point& endpoint) {
    lan::Reader in(bytes);
    const auto tag = in.u8();
    if (tag != projectedTag && tag != exactTag)
        throw std::runtime_error("Invalid projected laser tag");
    out.bytes.clear();
    out.u8(in.u8());
    // Six float words and one sample count, validated below with the native contract.
    Endpoints refs;
    for (unsigned k = 0; k < refs.count; ++k)
        for (auto& word : refs.values[k]) {
            word = in.u32();
            out.u32(word);
        }
    endpoint = refs.values[1];
    // Shape, scale and sample count follow the two world-space points.
    for (unsigned i = 0; i < 3; ++i)
        out.u32(in.u32());
    for (unsigned a = 0; a < 2; ++a) {
        const auto count = in.u16();
        if (count > maxLaserPoints)
            throw std::runtime_error("Invalid projected laser sample count");
        out.u16(count);
        const auto mode = static_cast<Array>(in.u8());
        const auto firstWord = out.bytes.size();
        if (mode == Array::literal) {
            for (unsigned i = 0; i < 2u * count; ++i)
                out.u32(in.u32());
        } else if (mode == Array::endpoints && count == 2) {
            for (unsigned i = 0; i < 2; ++i)
                for (auto word : refs.read(in))
                    out.u32(word);
        } else if (mode == Array::cubic && count > anchors) {
            const auto start = refs.read(in), end = refs.read(in);
            Fractions fractions;
            for (auto& value : fractions)
                value = std::bit_cast<std::int16_t>(in.u16());
            const auto points = controlPoints(start, end, fractions);
            for (unsigned i = 0; i < count; ++i)
                for (auto v : interpolate(points, count, i))
                    out.u32(std::bit_cast<std::uint32_t>(v));
        } else if (mode == Array::differences && count > 2) {
            std::array<std::uint32_t, 2> older{in.u32(), in.u32()}, last{in.u32(), in.u32()};
            for (auto bits : older)
                out.u32(bits);
            for (auto bits : last)
                out.u32(bits);
            for (unsigned i = 2; i < count; ++i)
                for (unsigned d = 0; d < 2; ++d) {
                    const auto z = varint(in);
                    const auto current = 2u * last[d] - older[d] + ((z >> 1) ^ (0u - (z & 1)));
                    out.u32(current);
                    older[d] = last[d];
                    last[d] = current;
                }
        } else
            throw std::runtime_error("Invalid projected laser array");
        if (a == 0 && count) {
            const std::span<const std::uint8_t> output(out.bytes);
            lan::Reader first(output.subspan(firstWord, 8)), last(output.last(8));
            refs.values[2] = {first.u32(), first.u32()};
            refs.values[3] = {last.u32(), last.u32()};
            refs.count = 4;
        }
    }
    in.finish();
    lan::Reader check(out.bytes);
    readLaserPath(check);
}
} // namespace isaac::presentation::laser_projection

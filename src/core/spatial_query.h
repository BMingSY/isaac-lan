#pragma once
#include <algorithm>
#include <cmath>
#include <compare>
#include <cstdint>
#include <limits>
#include <optional>
#include <utility>

namespace isaac::core::spatial_query {
struct Bounds {
    std::int32_t left, right, top, bottom;
};
struct Span {
    std::int32_t first, last;
};
struct Visit {
    std::int32_t y, x;
    auto operator<=>(const Visit&) const = default;
};
namespace detail {
inline constexpr std::uint64_t indexModulus = std::uint64_t{1} << 32;

// Sum floor((step * i + offset) / modulus), 0 <= i < count, by Euclid's
// algorithm. Our callers have count/modulus <= 2^32, step < 2^32 and
// offset < 2 * 2^32. The sum fits uint64_t, even when it exceeds INT64_MAX.
inline std::uint64_t floorSum(std::uint64_t count, std::uint64_t modulus, std::uint64_t step,
                              std::uint64_t offset) {
    std::uint64_t total = 0;
    while (count) {
        if (step >= modulus) {
            // Divide first: multiplying by the quotient before halving can
            // overflow even though this nonnegative contribution fits.
            const auto pairs = count % 2 ? count * ((count - 1) / 2) : (count / 2) * (count - 1);
            total += pairs * (step / modulus);
            step %= modulus;
        }
        if (offset >= modulus) {
            total += count * (offset / modulus);
            offset %= modulus;
        }
        // After reduction, this is at most (2^32 - 1) * 2^32 + 2^32 - 1.
        const auto end = step * count + offset;
        if (end < modulus)
            break;
        count = end / modulus;
        offset = end % modulus;
        std::swap(modulus, step);
    }
    return total;
}
inline std::uint64_t matchingRows(std::uint64_t count, std::uint64_t step, std::uint64_t offset,
                                  std::uint64_t columns) {
    // Adding modulus-columns crosses a modulus boundary precisely when the
    // original residue is >= columns. Subtract those non-matching rows.
    const auto outside = floorSum(count, indexModulus, step, offset + indexModulus - columns) -
                         floorSum(count, indexModulus, step, offset);
    return count - outside;
}
} // namespace detail

// The native loop visits rows then columns and computes its index modulo 2^32.
// For a row y, the first possible x is left + ((index-y*width-left) mod 2^32).
// Count matching rows with Euclid's algorithm, then binary-search the first one.
// This takes O(log^2(2^32)) per bucket, independent of the number of index wraps.
inline std::optional<Visit> firstVisit(Bounds box, std::int32_t width, std::int32_t index) {
    if (width <= 0 || index < 0 || box.right < box.left || box.bottom < box.top)
        return {};
    const auto columns = std::uint64_t(std::int64_t(box.right) - box.left + 1);
    const auto rows = std::uint64_t(std::int64_t(box.bottom) - box.top + 1);
    const auto residue = [&](std::int64_t y) {
        // The signed product and subtraction fit int64_t for int32_t inputs.
        // Conversion to uint32_t supplies the native modulo arithmetic.
        return static_cast<std::uint32_t>(std::int64_t(index) - y * width - box.left);
    };
    const std::uint64_t offset = residue(box.top);
    if (offset < columns)
        return Visit{box.top,
                     static_cast<std::int32_t>(std::int64_t(box.left) + std::int64_t(offset))};
    const auto step = detail::indexModulus - std::uint64_t(width);
    if (!detail::matchingRows(rows, step, offset, columns))
        return {};
    std::uint64_t before = 0, after = rows;
    while (after - before > 1) {
        const auto middle = before + (after - before) / 2;
        if (detail::matchingRows(middle, step, offset, columns))
            after = middle;
        else
            before = middle;
    }
    const auto y = std::int64_t(box.top) + std::int64_t(after - 1);
    const auto x = std::int64_t(box.left) + residue(y);
    return Visit{static_cast<std::int32_t>(y), static_cast<std::int32_t>(x)};
}

// The native broad phase uses y * width + x, including row aliases for x
// outside the grid. Wide rows overlap: their first visits form one interval.
// Preserve that interval and its order, rather than clamping x/y separately.
inline std::optional<Span> collapse(Bounds box, std::int32_t width, std::int32_t cells) {
    if (width <= 0 || cells <= 0 || box.bottom < box.top ||
        std::int64_t(box.right) - box.left + 1 < width)
        return {};
    const auto first = std::int64_t(box.top) * width + box.left;
    const auto last = std::int64_t(box.bottom) * width + box.right;
    if (first < std::numeric_limits<std::int32_t>::min() ||
        last > std::numeric_limits<std::int32_t>::max())
        return {};
    return Span{static_cast<std::int32_t>(std::max<std::int64_t>(0, first)),
                static_cast<std::int32_t>(std::min<std::int64_t>(cells - 1, last))};
}
inline std::optional<std::int32_t> coordinate(float position, float extent, float cell,
                                              bool upper) {
    // Round each operation to binary32, also on x87 builds. J460 uses subss /
    // addss, divss and cvttss2si; converting an out-of-range C++ float is UB.
    volatile float point = position, half = extent, step = cell;
    volatile float edge = upper ? point + half : point - half;
    volatile float quotient = edge / step;
    const double value = quotient;
    constexpr double firstInteger = std::numeric_limits<std::int32_t>::min();
    constexpr double pastLastInteger = double(std::numeric_limits<std::int32_t>::max()) + 1;
    if (!std::isfinite(value) || value < firstInteger || value >= pastLastInteger)
        return {};
    return static_cast<std::int32_t>(value);
}
struct Rectangle {
    float x, y, halfWidth, halfHeight;
};
inline std::optional<Rectangle> normalize(Rectangle value, float cell, std::int32_t width,
                                          std::int32_t cells) {
    constexpr std::int32_t maxNormalizedCells = 1 << 20;
    if (!std::isfinite(cell) || cell <= 0 || cells <= 0 || cells > maxNormalizedCells ||
        value.halfWidth < 0 || value.halfHeight < 0)
        return {};
    const auto left = coordinate(value.x, value.halfWidth, cell, false);
    const auto right = coordinate(value.x, value.halfWidth, cell, true);
    const auto top = coordinate(value.y, value.halfHeight, cell, false);
    const auto bottom = coordinate(value.y, value.halfHeight, cell, true);
    if (!left || !right || !top || !bottom)
        return {};
    const auto span = collapse({*left, *right, *top, *bottom}, width, cells);
    if (!span)
        return {};
    if (span->first > span->last)
        return Rectangle{0, 0, -1, -1};
    // A quarter-cell margin keeps both truncated endpoints inside their
    // positive cells. Verify the resulting float operations before using it.
    Rectangle result{(float(span->first + span->last) * 0.5f + 0.25f) * cell, 0,
                     float(span->last - span->first) * 0.5f * cell, 0};
    if (coordinate(result.x, result.halfWidth, cell, false) != span->first ||
        coordinate(result.x, result.halfWidth, cell, true) != span->last)
        return {};
    return result;
}
} // namespace isaac::core::spatial_query

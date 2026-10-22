#include "core/spatial_query.h"
#include "test_support.h"
#include <array>
#include <random>
#include <vector>

namespace query = isaac::core::spatial_query;
namespace {
constexpr auto firstInteger = std::numeric_limits<std::int32_t>::min();
constexpr auto lastInteger = std::numeric_limits<std::int32_t>::max();

// Independent oracle: execute the original row/column traversal with explicit
// 32-bit wrap, recording each valid bucket's first visit. Only small rectangles
// use this oracle; extreme-span cases below have independently known answers.
std::vector<std::pair<query::Visit, int>> nativeVisits(query::Bounds box, int width, int cells) {
    std::vector<bool> seen(cells);
    std::vector<std::pair<query::Visit, int>> result;
    for (std::int64_t y = box.top; y <= box.bottom; ++y)
        for (std::int64_t x = box.left; x <= box.right; ++x) {
            const auto index = std::uint32_t(y) * std::uint32_t(width) + std::uint32_t(x);
            if (index < unsigned(cells) && !seen[index]) {
                seen[index] = true;
                result.emplace_back(query::Visit{std::int32_t(y), std::int32_t(x)}, int(index));
            }
        }
    return result;
}
std::vector<int> indices(const std::vector<std::pair<query::Visit, int>>& visits) {
    std::vector<int> result;
    for (const auto& [visit, index] : visits)
        result.push_back(index);
    return result;
}
void checkVisits(query::Bounds box, int width, int cells) {
    const auto expected = nativeVisits(box, width, cells);
    std::vector<std::pair<query::Visit, int>> actual;
    for (int index = 0; index < cells; ++index)
        if (const auto visit = query::firstVisit(box, width, index))
            actual.emplace_back(*visit, index);
    std::sort(actual.begin(), actual.end());
    require(actual == expected, "Wrapped query changed native first-visit coordinates or order");
}
void orderedCandidates() {
    std::mt19937 random(8123);
    for (unsigned iteration = 0; iteration < 5000; ++iteration) {
        const int width = 1 + random() % 16, cells = 1 + random() % 256;
        const int left = int(random() % 128) - 64;
        const int top = int(random() % 128) - 64;
        const query::Bounds box{left, left + int(random() % 48), top, top + int(random() % 48)};
        if (const auto span = query::collapse(box, width, cells)) {
            std::vector<int> collapsed;
            for (int i = span->first; i <= span->last; ++i)
                collapsed.push_back(i);
            require(indices(nativeVisits(box, width, cells)) == collapsed,
                    "Collapsed query changed first-visit ordering or row aliases");
        }
    }
    const auto aliased = query::collapse({-3, 6, 1, 2}, 8, 24);
    require(aliased && aliased->first == 5 && aliased->last == 22,
            "Negative x aliases were incorrectly clipped to room width");
    require(!query::collapse({0, 2, 0, 8}, 8, 64), "Narrow disjoint rows were collapsed");
    require(!query::collapse({0, 8, 0, 8}, 0, 64), "Zero grid width was accepted");
    require(!query::collapse({0, 8, 2, 1}, 8, 64), "Reversed rows were accepted");
    require(!query::collapse({-100000, 100000, -100000, 100000}, 100000, 100),
            "Wrapped indices were collapsed without native modulo arithmetic");
    const auto huge = query::collapse({-100000, 100000, -100000, 100000}, 17, 221);
    require(huge && huge->first == 0 && huge->last == 220,
            "Huge finite query did not reduce to the existing grid");
}
void wrappedFirstVisits() {
    std::mt19937 random(713);
    constexpr std::array<int, 6> starts{firstInteger, firstInteger + 128, -(1 << 30),
                                        -64,          (1 << 30),          lastInteger - 48};
    for (unsigned iteration = 0; iteration < 2500; ++iteration) {
        const int width = 1 + random() % 128, cells = width * (1 + random() % 4);
        const auto left = starts[random() % starts.size()];
        const auto top = starts[random() % starts.size()];
        checkVisits({left, left + int(random() % 48), top, top + int(random() % 48)}, width, cells);
    }
    checkVisits({-1, 1, (1 << 30) - 1, (1 << 30) + 1}, 4, 8);
    checkVisits({-3, 6, 1, 2}, 8, 24);
    checkVisits({firstInteger, firstInteger + 3, lastInteger - 3, lastInteger}, lastInteger, 8);
    checkVisits({-4, 4, firstInteger, firstInteger + 4}, lastInteger, 8);
    require(!query::firstVisit({2, 1, 0, 1}, 1, 0), "Reversed columns were accepted");
    require(!query::firstVisit({0, 1, 2, 1}, 1, 0), "Reversed rows were accepted");
    require(!query::firstVisit({0, 1, 0, 1}, 0, 0), "Zero row width was accepted");
    require(!query::firstVisit({0, 1, 0, 1}, -1, 0), "Negative row width was accepted");
    require(!query::firstVisit({0, 1, 0, 1}, 1, -1), "Negative native bucket was accepted");
}
void extremeFirstVisits() {
    const query::Bounds wholeHeight{0, 0, firstInteger, lastInteger};
    require(query::firstVisit(wholeHeight, 1, 0) == query::Visit{0, 0},
            "Full 32-bit row count overflowed");
    require(query::firstVisit(wholeHeight, 1, lastInteger) == query::Visit{lastInteger, 0},
            "Binary search lost the last possible row");
    require(query::firstVisit(wholeHeight, 2, 0) == query::Visit{firstInteger, 0},
            "First row's wrapped index was ignored");
    require(!query::firstVisit(wholeHeight, 2, 1), "Impossible odd index was accepted");
    require(query::firstVisit(wholeHeight, lastInteger, 1) == query::Visit{lastInteger, 0},
            "Large odd row width changed the final modular hit");
    require(query::firstVisit({firstInteger, lastInteger, firstInteger, lastInteger}, lastInteger,
                              lastInteger) == query::Visit{firstInteger, -1},
            "Full 32-bit column span changed its first hit");
    require(query::firstVisit({-1, -1, lastInteger, lastInteger}, lastInteger, 0) ==
                query::Visit{lastInteger, -1},
            "Extreme signed product was not reduced modulo 2^32");
    require(query::firstVisit({firstInteger + 1, lastInteger, firstInteger, lastInteger}, 1, 0) ==
                query::Visit{firstInteger + 1, lastInteger},
            "Nearly full column span did not skip its excluded first-row residue");

    // A single column also has an independent modular-equation oracle. Remove
    // the power-of-two gcd and invert the odd multiplier by Newton iteration;
    // this covers full-height searches with arbitrary widths and signed x.
    std::mt19937 random(1987);
    for (unsigned iteration = 0; iteration < 1000; ++iteration) {
        const auto width = std::uint32_t(random() % lastInteger + 1);
        const auto x = std::int32_t(random());
        const auto index = std::int32_t(random() & std::uint32_t(lastInteger));
        const auto divisor = width & (0u - width);
        const auto difference = std::uint32_t(index) - std::uint32_t(x);
        const auto actual = query::firstVisit({x, x, firstInteger, lastInteger}, width, index);
        if (difference % divisor) {
            require(!actual, "A modular equation without solutions acquired a visit");
            continue;
        }
        const auto odd = width / divisor;
        std::uint32_t inverse = 1;
        for (unsigned bitDoubling = 0; bitDoubling < 5; ++bitDoubling)
            inverse *= 2u - odd * inverse;
        const auto period = (std::uint64_t{1} << 32) / divisor;
        const auto solution = (std::uint64_t(inverse) * (difference / divisor)) % period;
        const auto start = std::uint64_t(std::uint32_t(firstInteger)) % period;
        const auto distance = (solution + period - start) % period;
        const auto firstY = std::int32_t(std::int64_t(firstInteger) + std::int64_t(distance));
        require(actual == query::Visit{firstY, x},
                "Full-height first visit disagrees with the independent modular inverse");
    }

    // Every row index is a multiple of 65536, plus x=1. The other 65535 buckets
    // are unreachable. Enumerating index wraps per bucket would take >4 billion
    // iterations here, although the grid has only 65536 buckets.
    constexpr int width = 1 << 16;
    for (int index = 0; index < width; ++index) {
        const auto visit = query::firstVisit({1, 1, firstInteger, lastInteger}, width, index);
        if (index == 1)
            require(visit == query::Visit{firstInteger, 1}, "Reachable residue lost first row");
        else
            require(!visit, "Unreachable residue acquired a first visit");
    }
}
query::Bounds coordinates(query::Rectangle value, float cell) {
    return {*query::coordinate(value.x, value.halfWidth, cell, false),
            *query::coordinate(value.x, value.halfWidth, cell, true),
            *query::coordinate(value.y, value.halfHeight, cell, false),
            *query::coordinate(value.y, value.halfHeight, cell, true)};
}
void floatBounds() {
    std::mt19937 random(103);
    for (const float cell : {0.125f, 3.7f, 31.75f, 40.0f, 80.0f}) {
        for (unsigned iteration = 0; iteration < 1000; ++iteration) {
            const int width = 1 + random() % 16, cells = 1 + random() % 256;
            const query::Rectangle input{(int(random() % 128) - 64) * cell,
                                         (int(random() % 128) - 64) * cell,
                                         float(random() % 32) * cell, float(random() % 32) * cell};
            if (const auto normalized = query::normalize(input, cell, width, cells)) {
                const auto actual =
                    normalized->halfWidth < 0
                        ? std::vector<int>{}
                        : indices(nativeVisits(coordinates(*normalized, cell), width, cells));
                require(indices(nativeVisits(coordinates(input, cell), width, cells)) == actual,
                        "Normalized float bounds changed native candidate order");
            }
        }
        const auto huge = query::normalize({500, 300, 1000000, 1000000}, cell, 17, 221);
        require(huge && huge->halfHeight == 0, "Huge radius retained an unbounded row traversal");
    }
    for (const float invalid : {NAN, INFINITY, -INFINITY}) {
        require(!query::coordinate(invalid, 0, 1, false), "Nonfinite position was converted");
        require(!query::coordinate(0, invalid, 1, true), "Nonfinite extent was converted");
        require(!query::normalize({invalid, 0, 1, 1}, 40, 17, 221), "Nonfinite x was normalized");
        require(!query::normalize({0, invalid, 1, 1}, 40, 17, 221), "Nonfinite y was normalized");
        require(!query::normalize({0, 0, invalid, 1}, 40, 17, 221),
                "Nonfinite width was normalized");
        require(!query::normalize({0, 0, 1, invalid}, 40, 17, 221),
                "Nonfinite height was normalized");
        require(!query::normalize({0, 0, 1, 1}, invalid, 17, 221),
                "Nonfinite cell size was normalized");
    }
    for (const float cell : {0.0f, -1.0f})
        require(!query::normalize({0, 0, 1, 1}, cell, 17, 221), "Invalid cell size was accepted");
    require(!query::normalize({0, 0, -1, 1}, 40, 17, 221), "Negative extent was accepted");
    require(!query::normalize({0, 0, 1, 1}, 40, 17, 0), "Empty grid was normalized");
    require(!query::normalize({0, 0, 1, 1}, 40, 17, (1 << 20) + 1),
            "Oversized grid was normalized");
    require(query::coordinate(-0.5f, 0, 1, false) == 0 &&
                query::coordinate(-1.5f, 0, 1, false) == -1,
            "Native truncation was replaced with floor");
    constexpr float pastLast = 2147483648.0f;
    require(!query::coordinate(pastLast, 0, 1, true), "Integer overflow was accepted");
    require(query::coordinate(std::nextafter(pastLast, 0.0f), 0, 1, true) == 2147483520,
            "Last representable valid coordinate was rejected");
    require(query::coordinate(float(firstInteger), 0, 1, false) == firstInteger,
            "INT_MIN coordinate was rejected");
    require(!query::coordinate(std::nextafter(float(firstInteger), -INFINITY), 0, 1, false),
            "Coordinate below INT_MIN was accepted");
}
} // namespace
int main(int argc, char** argv) {
    return runTests(argc, argv,
                    {{"ordered-candidates", orderedCandidates},
                     {"wrapped-first-visits", wrappedFirstVisits},
                     {"extreme-first-visits", extremeFirstVisits},
                     {"float-bounds", floatBounds}});
}

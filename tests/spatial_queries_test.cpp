// Exercise the actual x86 query adapter, without launching Isaac.
#include "test_support.h"
#include "engine/versions/j460/spatial_queries.cpp"
#include <array>
#include <cstring>
#include <set>

using namespace isaac::engine::j460::spatial_queries;
using isaac::engine::j460::spatial_grid::Bucket;
using isaac::engine::j460::spatial_grid::QueryView;
namespace {
struct Result {
    std::vector<std::uintptr_t> values;
    unsigned capacity = 64;
    bool full = false;
};
unsigned calls = 0;
void* lastGrid = nullptr;
const Vector *lastPosition = nullptr, *lastExtent = nullptr;
bool observeOnly = false;
void* owner = reinterpret_cast<void*>(0x1234);

int nativeCoordinate(float position, float half, float cell, bool upper) {
    volatile float edge = upper ? position + half : position - half;
    volatile float quotient = edge / cell;
    const double value = quotient;
    return !std::isfinite(value) || value < -2147483648.0 || value >= 2147483648.0
               ? INT32_MIN
               : static_cast<int>(value);
}

void __attribute__((thiscall)) nativeQuery(void* grid, void* output, const Vector* position,
                                           const Vector* extent) {
    ++calls;
    lastGrid = grid;
    lastPosition = position;
    lastExtent = extent;
    if (observeOnly)
        return;
    const auto& view = *static_cast<QueryView*>(grid);
    require(view.owner == owner, "Query changed the native UID deduplication owner");
    auto& result = *static_cast<Result*>(output);
    const auto left = nativeCoordinate(position->x, extent->x, view.cell, false);
    const auto right = nativeCoordinate(position->x, extent->x, view.cell, true);
    const auto top = nativeCoordinate(position->y, extent->y, view.cell, false);
    const auto bottom = nativeCoordinate(position->y, extent->y, view.cell, true);
    const auto rows = std::int64_t(bottom) - top + 1;
    const auto columns = std::int64_t(right) - left + 1;
    // Fail before a broken adapter can turn this regression into a huge loop.
    require(rows <= 0 || columns <= 0 || rows <= 1000000 / columns,
            "Adapter forwarded an excessive native coordinate traversal");
    std::set<std::uintptr_t> seen;
    for (std::int64_t y = top; y <= bottom; ++y)
        for (std::int64_t x = left; x <= right; ++x) {
            const auto index = static_cast<std::uint32_t>(y * view.width + x);
            if (index >= static_cast<unsigned>(view.end - view.begin))
                continue;
            const auto& bucket = view.begin[index];
            require(bucket.count >= 0 && bucket.count <= 40, "Borrowed bucket is invalid");
            for (int i = 0; i < bucket.count; ++i)
                if (seen.insert(bucket.entities[i]).second) {
                    if (result.values.size() >= result.capacity)
                        result.full = true;
                    // Native Query logs a capacity excess and still appends.
                    // Use vector storage here without inventing truncation safety.
                    result.values.push_back(bucket.entities[i]);
                }
        }
}

void reset() {
    calls = 0;
    lastGrid = nullptr;
    lastPosition = lastExtent = nullptr;
    observeOnly = false;
}
} // namespace

int main() {
    static_assert(sizeof(void*) == 4);
    original = nativeQuery;
    std::array<Bucket, 8> buckets{};
    for (unsigned i = 0; i < buckets.size(); ++i) {
        buckets[i].count = 2;
        buckets[i].entities[0] = 100 + i;
        buckets[i].entities[1] = 777;
    }
    const auto before = buckets;
    QueryView grid{owner, {}, 4, 2, 1, buckets.data(), buckets.data() + buckets.size()};
    const auto originalGrid = grid;
    const std::vector<std::uintptr_t> expected{900, 100, 777, 101, 102, 103, 104, 105, 106, 107};

    for (const bool wrapped : {false, true, false, true}) {
        reset();
        const Vector center{0, wrapped ? float(1 << 30) : 0}, extent{1000, 128};
        const auto savedCenter = center, savedExtent = extent;
        Result result{{900}};
        query(&grid, nullptr, &result, &center, &extent);
        require(calls == 1 && result.values == expected && !result.full,
                "Query changed first-visit order, duplicate removal or existing output");
        require((lastGrid != &grid) == wrapped, "Query did not select the expected native view");
        require(std::memcmp(&center, &savedCenter, sizeof(center)) == 0 &&
                    std::memcmp(&extent, &savedExtent, sizeof(extent)) == 0,
                "Exact-filter arguments changed");
        require(std::memcmp(before.data(), buckets.data(), sizeof(buckets)) == 0 &&
                    std::memcmp(&grid, &originalGrid, sizeof(grid)) == 0,
                "Query changed native bucket storage or its owner");
    }

    reset();
    const Vector smallCenter{1.5f, 1.5f}, smallExtent{0.1f, 0.1f};
    Result small;
    query(&grid, nullptr, &small, &smallCenter, &smallExtent);
    require(calls == 1 && lastGrid == &grid && lastPosition == &smallCenter &&
                lastExtent == &smallExtent &&
                small.values == std::vector<std::uintptr_t>({105, 777}),
            "Ordinary query did not preserve the original call");

    reset();
    const Vector outside{-100000, -100000}, emptyExtent{1000, 1000};
    Result empty{{900}};
    query(&grid, nullptr, &empty, &outside, &emptyExtent);
    require(!calls && empty.values == std::vector<std::uintptr_t>({900}),
            "An empty broad phase changed existing output");

    reset();
    const Vector wrappedCenter{0, float(1 << 30)}, largeExtent{1000, 128};
    Result limited{{900}, 3};
    query(&grid, nullptr, &limited, &wrappedCenter, &largeExtent);
    require(calls == 1 && limited.full && limited.values == expected && limited.capacity == 3,
            "Adapter truncated native candidates or changed the result capacity");

    for (const bool invalidBucket : {false, true}) {
        reset();
        observeOnly = true;
        auto invalid = grid;
        if (invalidBucket)
            buckets[0].count = 41;
        else
            invalid.width = 0;
        Result untouched{{900}};
        query(&invalid, nullptr, &untouched, &wrappedCenter, &largeExtent);
        require(calls == 1 && lastGrid == &invalid && lastPosition == &wrappedCenter &&
                    lastExtent == &largeExtent &&
                    untouched.values == std::vector<std::uintptr_t>({900}),
                "Inapplicable native layout partially replaced the call");
        buckets = before;
    }
}

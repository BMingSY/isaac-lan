#include "engine/versions/j460/spatial_queries.h"
#include "engine/versions/j460/entrypoints.h"
#include "engine/versions/j460/layout.h"
#include "engine/versions/j460/spatial_grid.h"
#include "core/spatial_query.h"
#include <MinHook.h>
#include <algorithm>
#include <new>
#include <vector>

namespace isaac::engine::j460::spatial_queries {
namespace {
struct Vector {
    float x, y;
};
using Query = void(__attribute__((thiscall)) *)(void*, void*, const Vector*, const Vector*);
Query original = nullptr;
constexpr unsigned maxQueryCells = 1 << 20, nativeVisitRatio = 4;
template <class T> T field(void* value, unsigned offset) {
    return *reinterpret_cast<const T*>(static_cast<const char*>(value) + offset);
}

bool queryBorrowed(void* grid, void* result, core::spatial_query::Bounds box, int width,
                   unsigned cells) {
    namespace bounds = core::spatial_query;
    std::vector<std::pair<bounds::Visit, unsigned>> order;
    std::vector<spatial_grid::Bucket> buckets;
    try {
        order.reserve(cells);
        for (unsigned i = 0; i < cells; ++i)
            if (const auto visit = bounds::firstVisit(box, width, static_cast<int>(i)))
                order.emplace_back(*visit, i);
        if (order.empty())
            return true;
        std::sort(order.begin(), order.end());
        const auto* source = field<const spatial_grid::Bucket*>(grid, layout::spatialGrid::begin);
        buckets.reserve(order.size());
        for (const auto& [visit, index] : order) {
            (void)visit;
            if (source[index].count < 0 ||
                source[index].count > int(layout::spatialGrid::bucketCapacity))
                return false;
            buckets.push_back(source[index]);
        }
    } catch (const std::bad_alloc&) {
        // Do not unwind a MinGW allocation failure through a native MSVC call.
        // No original bucket, entity or result has been changed at this point.
        return false;
    }
    spatial_grid::QueryView view{field<void*>(grid, 0),          {}, 1, 1, 1, buckets.data(),
                                 buckets.data() + buckets.size()};
    const Vector center{float(buckets.size() - 1) * 0.5f + 0.25f, 0};
    const Vector extent{float(buckets.size() - 1) * 0.5f, 0};
    // One original call retains native UID deduplication and output capacity.
    // The caller still uses its original geometry for the exact filter.
    original(&view, result, &center, &extent);
    return true;
}

void __attribute__((fastcall)) query(void* grid, void*, void* result, const Vector* position,
                                     const Vector* extent) {
    namespace bounds = core::spatial_query;
    const auto first = field<std::uintptr_t>(grid, layout::spatialGrid::begin);
    const auto last = field<std::uintptr_t>(grid, layout::spatialGrid::end);
    if (last >= first && (last - first) % layout::spatialGrid::bucketSize == 0) {
        const auto cells = (last - first) / layout::spatialGrid::bucketSize;
        const int width = field<int>(grid, layout::spatialGrid::width);
        const float cell = field<float>(grid, layout::spatialGrid::cellSize);
        if (cells && cells <= maxQueryCells && width > 0 && unsigned(width) <= cells &&
            std::isfinite(cell) && cell > 0) {
            const auto coordinate = [cell](float point, float half, bool upper) {
                // Match native cvttss2si for non-finite/out-of-range floats.
                return bounds::coordinate(point, half, cell, upper).value_or(INT32_MIN);
            };
            const bounds::Bounds box{coordinate(position->x, extent->x, false),
                                     coordinate(position->x, extent->x, true),
                                     coordinate(position->y, extent->y, false),
                                     coordinate(position->y, extent->y, true)};
            const auto rows = std::int64_t(box.bottom) - box.top + 1;
            const auto columns = std::int64_t(box.right) - box.left + 1;
            if (rows > 0 && columns > 0 &&
                columns > std::int64_t(nativeVisitRatio) * cells / rows) {
                const auto normalized =
                    bounds::normalize({position->x, position->y, extent->x, extent->y}, cell, width,
                                      static_cast<int>(cells));
                if (normalized) {
                    if (normalized->halfWidth < 0)
                        return;
                    const Vector center{normalized->x, normalized->y};
                    const Vector halfSize{normalized->halfWidth, normalized->halfHeight};
                    original(grid, result, &center, &halfSize);
                    return;
                }
                if (queryBorrowed(grid, result, box, width, cells))
                    return;
            }
        }
    }
    original(grid, result, position, extent);
}
} // namespace

bool install(std::uintptr_t image) {
    auto* target = reinterpret_cast<void*>(image + entry::spatialGridQuery);
    return MH_CreateHook(target, reinterpret_cast<void*>(query),
                         reinterpret_cast<void**>(&original)) == MH_OK &&
           MH_EnableHook(target) == MH_OK;
}
} // namespace isaac::engine::j460::spatial_queries

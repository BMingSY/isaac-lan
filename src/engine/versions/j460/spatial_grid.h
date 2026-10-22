#pragma once
#include "engine/versions/j460/layout.h"
#include <cstddef>
#include <cstdint>

namespace isaac::engine::j460::spatial_grid {
struct Bucket {
    std::uintptr_t entities[layout::spatialGrid::bucketCapacity];
    int count;
};
static_assert(sizeof(Bucket) == layout::spatialGrid::bucketSize);

// Query only borrows this prefix during its call. No native constructor,
// destructor or stored reference may receive this temporary view.
struct QueryView {
    void* owner;
    int unused[2];
    int width, height;
    float cell;
    Bucket *begin, *end;
};
static_assert(sizeof(QueryView) == 0x20);
static_assert(offsetof(QueryView, width) == layout::spatialGrid::width);
static_assert(offsetof(QueryView, cell) == layout::spatialGrid::cellSize);
static_assert(offsetof(QueryView, begin) == layout::spatialGrid::begin);
static_assert(offsetof(QueryView, end) == layout::spatialGrid::end);
} // namespace isaac::engine::j460::spatial_grid

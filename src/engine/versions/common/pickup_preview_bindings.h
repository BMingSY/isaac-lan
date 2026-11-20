#pragma once
#include <cstdint>

namespace isaac::engine::native_pickup_preview {
struct Bindings {
    std::uint32_t update, game;
    unsigned room, entities, renderArray, data, count, type;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_pickup_preview

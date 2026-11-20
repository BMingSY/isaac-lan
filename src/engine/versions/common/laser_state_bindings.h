#pragma once
#include <array>
namespace isaac::engine::native_laser_state {
struct Bindings {
    unsigned allocate, release;
    unsigned sprite, type, sampleState, samples;
    std::array<unsigned, 6> values;
    std::array<unsigned, 2> paths;
};
extern const Bindings bindings;
} // namespace isaac::engine::native_laser_state

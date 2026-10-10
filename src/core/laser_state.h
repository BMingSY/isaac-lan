#pragma once
#include "net/protocol.h"
#include <bit>
#include <cmath>

namespace isaac::presentation {
struct LaserPath {
    std::uint8_t sampleState;
    std::array<std::uint32_t, 6> values;
    std::uint32_t samples;
    std::array<std::vector<std::uint32_t>, 2> paths;
};
inline LaserPath readLaserPath(lan::Reader& bytes) {
    LaserPath result;
    result.sampleState = bytes.u8();
    // J460's constructor writes -1 until Update determines whether to sample.
    // This native byte is a tri-state, despite its public boolean accessor.
    if (result.sampleState > 1 && result.sampleState != 255)
        throw std::runtime_error("Invalid laser sample state");
    auto number = [&] {
        const auto bits = bytes.u32();
        if (!std::isfinite(std::bit_cast<float>(bits)))
            throw std::runtime_error("Invalid laser coordinate");
        return bits;
    };
    for (auto& value : result.values)
        value = number();
    result.samples = bytes.u32();
    if (result.samples > 2048)
        throw std::runtime_error("Invalid laser sample count");
    for (auto& path : result.paths) {
        const auto count = bytes.u16();
        if (count > 2048)
            throw std::runtime_error("Laser path too long");
        path.resize(count * 2);
        for (auto& value : path)
            value = number();
    }
    bytes.finish();
    return result;
}
} // namespace isaac::presentation

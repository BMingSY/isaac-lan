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
inline void translateLaserPath(LaserPath& path, float x, float y) {
    if (!std::isfinite(x) || !std::isfinite(y))
        throw std::runtime_error("Invalid laser render offset");
    auto translate = [](std::uint32_t& value, float offset) {
        const auto coordinate = std::bit_cast<float>(value) + offset;
        if (!std::isfinite(coordinate))
            throw std::runtime_error("Invalid translated laser coordinate");
        value = std::bit_cast<std::uint32_t>(coordinate);
    };
    // Origin and endpoint are world coordinates; the remaining two values
    // carry shape/scale and must not be translated.
    for (unsigned i = 0; i < 4; ++i)
        translate(path.values[i], i % 2 ? y : x);
    for (auto& points : path.paths)
        for (std::size_t i = 0; i < points.size(); ++i)
            translate(points[i], i % 2 ? y : x);
}
} // namespace isaac::presentation

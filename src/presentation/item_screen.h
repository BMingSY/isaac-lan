#pragma once
#include "net/protocol.h"
#include <algorithm>
#include <bit>
#include <cmath>
#include <limits>

namespace isaac::presentation {
// Native postprocess scalars, owned by a peer rather than the global viewport.
struct ItemScreen {
    static constexpr unsigned maxDuration = std::numeric_limits<int>::max();
    static constexpr float maxDizzyMagnitude = 65535;
    unsigned pixels = 0, pixelDuration = 0;
    float dizzy = 0, target = 0, step = 0.001f;
    unsigned bloom = 0, bloomDuration = 0;
    float bloomIntensity = 1;
    void advance() {
        if (pixels)
            --pixels;
        if (bloom)
            --bloom;
        dizzy += std::clamp(target - dizzy, -step, step);
    }
    void pixelate(unsigned duration) {
        pixels = pixelDuration = std::max(pixels, duration);
    }
    void write(lan::Writer& w) const {
        w.u32(pixels);
        w.u32(pixelDuration);
        for (float value : {dizzy, target, step})
            w.u32(std::bit_cast<unsigned>(value));
        w.u32(bloom);
        w.u32(bloomDuration);
        w.u32(std::bit_cast<unsigned>(bloomIntensity));
    }
    static ItemScreen read(lan::Reader& r) {
        ItemScreen value;
        value.pixels = r.u32();
        value.pixelDuration = r.u32();
        value.dizzy = std::bit_cast<float>(r.u32());
        value.target = std::bit_cast<float>(r.u32());
        value.step = std::bit_cast<float>(r.u32());
        value.bloom = r.u32();
        value.bloomDuration = r.u32();
        value.bloomIntensity = std::bit_cast<float>(r.u32());
        if (value.pixels > value.pixelDuration || value.pixelDuration > maxDuration)
            throw std::runtime_error("Invalid pixelation duration");
        if (value.bloom > value.bloomDuration || value.bloomDuration > maxDuration)
            throw std::runtime_error("Invalid bloom duration");
        for (float scalar : {value.dizzy, value.target, value.step, value.bloomIntensity})
            if (!std::isfinite(scalar) || scalar < 0 || scalar > maxDizzyMagnitude)
                throw std::runtime_error("Invalid item screen effect");
        return value;
    }
};
} // namespace isaac::presentation

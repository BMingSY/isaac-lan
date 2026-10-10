#pragma once
#include "net/protocol.h"

namespace isaac::input {
// One local source shared by network capture and render-time prediction.
// Stale decisions retain ownership but release gameplay controls.
class AutomationInput {
    bool enabled = false;
    std::uint8_t held = 0, edges = 0;
    std::uint32_t updated = 0;

  public:
    void set(bool active, std::uint8_t buttons, std::uint32_t frame) {
        if (!active) {
            clear();
            return;
        }
        if (!enabled || frame - updated > 3)
            held = edges = 0;
        enabled = true;
        edges |= buttons & ~held;
        held = buttons;
        updated = frame;
    }
    void clear() {
        enabled = false;
        held = edges = 0;
    }
    lan::InputFrame compose(lan::InputFrame physical, std::uint32_t frame, bool consume) {
        if (!enabled)
            return physical;
        if (frame - updated > 3)
            held = edges = 0;
        for (unsigned action = 0; action < 8; ++action)
            physical.values[action] = (held & (1u << action)) ? 65535 : 0;
        physical.triggered = (physical.triggered & 0xff00u) | edges;
        if (consume)
            edges = 0;
        return physical;
    }
};
} // namespace isaac::input

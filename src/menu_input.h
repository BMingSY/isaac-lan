#pragma once
#include "net_protocol.h"

namespace isaac::input {
inline void keyboardPause(lan::InputFrame& input, bool paused) {
    // J460 accepts keyboard Escape as MENU_BACK only on controller zero.
    // LAN actors use controllers 1..4, whose pause entry requires MENU_PAUSE.
    // Keep Back unchanged inside a menu so its native navigation still works.
    if (!paused && (input.triggered & (1u << 15))) {
        input.triggered |= 1u << 12;
        input.values[12] = 65535;
    }
}
} // namespace isaac::input

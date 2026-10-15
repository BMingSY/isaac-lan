#include "runtime/input_schedule.h"
#include "test_support.h"
#include <cstdio>

int main() {
    isaac::runtime::InputSchedule host, guest;
    unsigned hostSamples = 0, guestSamples = 0;
    for (unsigned frame = 0; frame < 120; ++frame) {
        // Poll before a native full/half update, then again before/after render.
        hostSamples += host.capture(true, false, frame);
        guestSamples += guest.capture(false, false, frame);
        if (frame % 2 == 0) {
            hostSamples += host.capture(true, true, frame);
            guestSamples += guest.capture(false, true, frame);
        }
        for (unsigned poll = 0; poll < 3; ++poll) {
            hostSamples += host.capture(true, false, frame);
            guestSamples += guest.capture(false, false, frame);
        }
    }
    require(hostSamples == 60 && guestSamples == 120, "Input cadence invariant failed");
    // After a stall capture only the current frame, never replay missed input.
    require(guest.capture(false, false, 500), "Input cadence invariant failed");
    require(!guest.capture(false, true, 500), "Input cadence invariant failed");
    // A native host update cannot stall on a separate input/render clock.
    require(host.capture(true, true, 500), "Input cadence invariant failed");
    require(host.capture(true, true, 500), "Input cadence invariant failed");
    guest = isaac::runtime::InputSchedule{};
    require(guest.capture(false, false, 500), "Input cadence invariant failed");
    require(guest.capture(false, false, 0xffffffffu), "Input cadence invariant failed");
    require(guest.capture(false, false, 0), "Input cadence invariant failed");
    isaac::runtime::InputSchedule slowerGuest(30), slowerHost(30);
    unsigned slowSamples = 0;
    for (unsigned frame = 0; frame < 120; ++frame) {
        slowSamples += slowerGuest.capture(false, false, frame);
        require(!slowerGuest.capture(false, true, frame), "Repeated poll bypassed 30 Hz input");
        require(!slowerHost.capture(true, false, frame), "Host sampled outside simulation");
        require(slowerHost.capture(true, true, frame), "Guest setting throttled host simulation");
    }
    require(slowSamples == 60, "30 Hz setting did not skip alternating render frames");
    require(slowerGuest.capture(false, false, 501), "Stall delayed current input");
    require(!slowerGuest.capture(false, false, 502), "Stall replayed missed input");
    require(slowerGuest.capture(false, false, 503), "Input cadence did not resume after a stall");
    slowerGuest = isaac::runtime::InputSchedule(30);
    require(slowerGuest.capture(false, false, 0xfffffffeu), "Session reset retained its timer");
    require(!slowerGuest.capture(false, false, 0xffffffffu), "30 Hz frame gap was lost");
    require(slowerGuest.capture(false, false, 0), "Frame counter wrap delayed input");
    std::puts(
        "PASS guest render cadence, host simulation cadence, repeated polls, stall and reset");
}

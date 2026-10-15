#pragma once
#include <cstdint>
#include <optional>

namespace isaac::runtime {
// Input service runs at several boundaries within each native render frame.
// Guest samples are coalesced there; host samples follow simulation calls.
class InputSchedule {
    std::optional<std::uint32_t> capturedFrame;
    unsigned intervalFrames;

  public:
    explicit InputSchedule(unsigned hz = 60) : intervalFrames(hz == 30 ? 2 : 1) {}
    bool capture(bool host, bool simulationStep, std::uint32_t frame) {
        if (host ? !simulationStep : capturedFrame && frame - *capturedFrame < intervalFrames)
            return false;
        capturedFrame = frame;
        return true;
    }
};
} // namespace isaac::runtime

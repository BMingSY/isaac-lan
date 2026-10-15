#pragma once
#include <cstdint>
#include <optional>

namespace isaac::runtime {
// Input service runs at several boundaries within each native render frame.
// Guest samples are coalesced there; host samples follow simulation calls.
class InputSchedule {
    std::optional<std::uint32_t> capturedFrame;

  public:
    bool capture(bool host, bool simulationStep, std::uint32_t frame) {
        if (host ? !simulationStep : capturedFrame == frame)
            return false;
        capturedFrame = frame;
        return true;
    }
};
} // namespace isaac::runtime

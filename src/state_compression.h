#pragma once
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

namespace isaac::lan {
// Windows' bounded buffer-mode XPRESS codec; packets remain independent so a
// newly joined client never needs previous snapshots to decode current state.
class StateCompression {
    struct Impl;
    std::unique_ptr<Impl> impl;
public:
    StateCompression();
    ~StateCompression();
    std::vector<std::uint8_t> compress(std::span<const std::uint8_t> bytes);
    std::vector<std::uint8_t> expand(std::span<const std::uint8_t> bytes);
};
}

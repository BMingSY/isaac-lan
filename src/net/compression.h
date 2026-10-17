#pragma once
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

namespace isaac::lan {
// Bounded checksummed Zstd frames, optionally referencing an acknowledged view.
// The DEFLATE/XPRESS readers remain for previous trace archives.
class StateCompression {
    struct Impl;
    std::unique_ptr<Impl> impl;

  public:
    enum Mode : std::uint8_t { raw, xpress, deflate, zstd, zstdPrefix };
    StateCompression();
    ~StateCompression();
    std::vector<std::uint8_t> compress(std::span<const std::uint8_t> bytes,
                                       std::span<const std::uint8_t> baseline = {});
    std::vector<std::uint8_t> expand(std::span<const std::uint8_t> bytes,
                                     std::span<const std::uint8_t> baseline = {});
};
} // namespace isaac::lan

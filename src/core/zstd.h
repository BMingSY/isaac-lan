#pragma once
#include <cstdint>
#include <memory>
#include <span>
#include <vector>

namespace isaac::compression {
// Independent checksummed frames. A caller may supply an immutable, acknowledged
// prefix; no pointer into the prefix survives the operation.
class Zstd {
    struct Impl;
    std::unique_ptr<Impl> impl;

  public:
    Zstd();
    ~Zstd();
    std::vector<std::uint8_t> compress(std::span<const std::uint8_t> value, std::size_t limit,
                                       std::span<const std::uint8_t> prefix = {});
    std::vector<std::uint8_t> expand(std::span<const std::uint8_t> frame, std::size_t size,
                                     std::size_t limit, std::span<const std::uint8_t> prefix = {});
    std::size_t memory() const;
};
} // namespace isaac::compression

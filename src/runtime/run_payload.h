#pragma once
#include <cstddef>
#include <cstdint>
#include <span>
#include <stdexcept>
#include <vector>

namespace isaac::runtime {
// Owned portable bridge state travels with the native checkpoint. The runtime
// bounds and retains bytes; the bridge validates their gameplay schema.
inline constexpr std::size_t maxRunPayloadSize = 64 * 1024;
class RunPayload {
    std::vector<std::uint8_t> bytes_;
    std::uint32_t revision_ = 0;

  public:
    void restore(std::span<const std::uint8_t> bytes) {
        if (bytes.size() > maxRunPayloadSize)
            throw std::runtime_error("Run state exceeds checkpoint limit");
        bytes_.assign(bytes.begin(), bytes.end());
        ++revision_;
    }
    const std::vector<std::uint8_t>& bytes() const {
        return bytes_;
    }
    std::uint32_t revision() const {
        return revision_;
    }
};
} // namespace isaac::runtime

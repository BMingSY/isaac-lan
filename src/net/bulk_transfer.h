#pragma once
#include "net/protocol.h"
#include <memory>

namespace isaac::lan {
inline constexpr std::size_t bulkChunkSize = 3000;
inline std::span<const std::uint8_t> bulkChunk(std::span<const std::uint8_t> bytes,
                                               std::size_t offset) {
    if (offset > bytes.size())
        throw std::runtime_error("Invalid bulk send offset");
    return bytes.subspan(offset, std::min(bulkChunkSize, bytes.size() - offset));
}
inline void appendBulkChunk(std::vector<std::uint8_t>& target, std::size_t total,
                            std::size_t offset, std::span<const std::uint8_t> bytes,
                            std::size_t limit) {
    if (total > limit || offset != target.size() || offset > total ||
        bytes.size() > bulkChunkSize || bytes.size() > total - offset || (total && bytes.empty()))
        throw std::runtime_error("Invalid bulk transfer chunk");
    if (!offset)
        target.reserve(total);
    target.insert(target.end(), bytes.begin(), bytes.end());
}
} // namespace isaac::lan

#pragma once
#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace isaac::core::record_delta {
using Bytes = std::span<const std::uint8_t>;
// A declared collection of opaque state tuples. The first three integers are
// the identity and two grouping keys. Two more integers complete the creation
// header. The frame prefix and the rest of every tuple belong to the application.
bool framed(Bytes value);
std::vector<std::uint8_t> encode(Bytes value, Bytes baseline);
std::vector<std::uint8_t> expand(Bytes patch, Bytes baseline, std::size_t expectedSize);
} // namespace isaac::core::record_delta

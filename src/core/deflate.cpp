#include "core/deflate.h"
#include "miniz.h"
#include <stdexcept>

namespace isaac::compression {
std::vector<std::uint8_t> deflate(std::span<const std::uint8_t> input, std::size_t limit) {
    if (input.empty() || input.size() > limit)
        throw std::runtime_error("Invalid deflate input size");
    std::vector<std::uint8_t> output(mz_compressBound(input.size()));
    mz_ulong size = output.size();
    if (mz_compress2(output.data(), &size, input.data(), input.size(), MZ_BEST_SPEED) != MZ_OK)
        throw std::runtime_error("Cannot compress state");
    output.resize(size);
    return output;
}
std::vector<std::uint8_t> inflate(std::span<const std::uint8_t> input, std::size_t size,
                                  std::size_t limit) {
    if (input.empty() || !size || size > limit)
        throw std::runtime_error("Invalid inflate size");
    std::vector<std::uint8_t> output(size);
    mz_ulong written = size, consumed = input.size();
    if (mz_uncompress2(output.data(), &written, input.data(), &consumed) != MZ_OK ||
        written != size || consumed != input.size())
        throw std::runtime_error("Invalid deflate state");
    return output;
}
} // namespace isaac::compression

#pragma once
#include <bit>
#include <cmath>
#include <cstdint>
#include <limits>
#include <span>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace isaac::state_codec {
// Contract shared with bridge/sync/codec.lua; differential tests freeze the bytes.
enum class Tag : std::uint8_t { falseValue, trueValue, int32, int64, float32, string, array };
inline constexpr std::size_t maxDepth = 12, maxNodes = 250000, maxLength = 65535;
inline constexpr std::size_t maxBytes = 2 * 1024 * 1024;

struct Budget {
    std::size_t nodes = 0;
    void visit(std::size_t depth, std::size_t count = 1) {
        if (depth >= maxDepth || count >= maxNodes || nodes >= maxNodes - count)
            throw std::runtime_error("State structure exceeded");
        nodes += count;
    }
};

class Writer {
    std::vector<std::uint8_t> bytes;
    void integer(std::uint64_t value, unsigned width) {
        if (bytes.size() + width > maxBytes)
            throw std::runtime_error("State size exceeded");
        for (unsigned i = width; i > 0; --i)
            bytes.push_back(static_cast<std::uint8_t>(value >> ((i - 1) * 8)));
    }

  public:
    Writer() {
        bytes.reserve(4096);
    }
    std::span<const std::uint8_t> data() const {
        return bytes;
    }
    void append(std::span<const std::uint8_t> value) {
        if (value.size() > maxBytes - bytes.size())
            throw std::runtime_error("State size exceeded");
        bytes.insert(bytes.end(), value.begin(), value.end());
    }
    void boolean(bool value) {
        integer(static_cast<unsigned>(value ? Tag::trueValue : Tag::falseValue), 1);
    }
    void number(std::int64_t value) {
        const bool narrow = value >= std::numeric_limits<std::int32_t>::min() &&
                            value <= std::numeric_limits<std::int32_t>::max();
        integer(static_cast<unsigned>(narrow ? Tag::int32 : Tag::int64), 1);
        integer(static_cast<std::uint64_t>(value), narrow ? 4 : 8);
    }
    void number(double value) {
        const auto packed = static_cast<float>(value);
        if (!std::isfinite(value) || !std::isfinite(packed))
            throw std::runtime_error("Non-finite or overflowing float32 state value");
        integer(static_cast<unsigned>(Tag::float32), 1);
        integer(std::bit_cast<std::uint32_t>(packed), 4);
    }
    void string(std::string_view value) {
        if (value.size() > maxLength)
            throw std::runtime_error("State string exceeded");
        integer(static_cast<unsigned>(Tag::string), 1);
        integer(value.size(), 2);
        append({reinterpret_cast<const std::uint8_t*>(value.data()), value.size()});
    }
    void array(std::size_t size) {
        if (size > maxLength)
            throw std::runtime_error("State array exceeded");
        integer(static_cast<unsigned>(Tag::array), 1);
        integer(size, 2);
    }
};

class Reader {
    std::span<const std::uint8_t> bytes;
    std::size_t cursor = 0;

  public:
    explicit Reader(std::span<const std::uint8_t> value) : bytes(value) {
        if (value.size() > maxBytes)
            throw std::runtime_error("State size exceeded");
    }
    std::uint64_t integer(unsigned width) {
        if (width > bytes.size() - cursor)
            throw std::runtime_error("Truncated state value");
        std::uint64_t result = 0;
        for (unsigned i = 0; i < width; ++i)
            result = (result << 8) | bytes[cursor++];
        return result;
    }
    Tag tag() {
        const auto value = integer(1);
        if (value > static_cast<unsigned>(Tag::array))
            throw std::runtime_error("Unknown state value tag");
        return static_cast<Tag>(value);
    }
    double number() {
        const auto value = std::bit_cast<float>(static_cast<std::uint32_t>(integer(4)));
        if (!std::isfinite(value))
            throw std::runtime_error("Non-finite state value");
        return value;
    }
    std::string_view string() {
        const auto size = static_cast<std::size_t>(integer(2));
        if (size > bytes.size() - cursor)
            throw std::runtime_error("Truncated state string");
        const auto result =
            std::string_view(reinterpret_cast<const char*>(bytes.data() + cursor), size);
        cursor += size;
        return result;
    }
    void finish() const {
        if (cursor != bytes.size())
            throw std::runtime_error("Trailing state bytes");
    }
};
} // namespace isaac::state_codec

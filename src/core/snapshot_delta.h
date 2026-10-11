#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <unordered_map>
#include <vector>

namespace isaac::core {
// Pointer-free byte patches. Copy offsets refer only to the immutable baseline,
// never to partially reconstructed output; insertions do not shift references.
class SnapshotDelta {
    static constexpr std::size_t block = 16, candidates = 4;
    static constexpr std::uint64_t multiplier = 257;
    struct Matches {
        std::array<std::uint32_t, candidates> offsets{};
        unsigned count = 0;
    };
    static std::uint64_t hash(std::span<const std::uint8_t> bytes) {
        std::uint64_t result = 14695981039346656037ull;
        for (auto value : bytes) {
            result ^= value;
            result *= 1099511628211ull;
        }
        return result;
    }
    static void number(std::vector<std::uint8_t>& out, std::uint32_t value) {
        do {
            const auto next = value >> 7;
            out.push_back(static_cast<std::uint8_t>((value & 127) | (next ? 128 : 0)));
            value = next;
        } while (value);
    }
    static void checksum(std::vector<std::uint8_t>& out, std::uint64_t value) {
        for (unsigned i = 0; i < 8; ++i)
            out.push_back(static_cast<std::uint8_t>(value >> (i * 8)));
    }
    static std::uint64_t window(std::span<const std::uint8_t> bytes) {
        std::uint64_t value = 0;
        for (auto byte : bytes.first(block))
            value = value * multiplier + byte;
        return value;
    }

  public:
    static constexpr std::size_t limit = 2 * 1024 * 1024;
    static std::optional<std::vector<std::uint8_t>> encode(std::span<const std::uint8_t> base,
                                                           std::span<const std::uint8_t> value) {
        if (base.empty() || value.empty() || base.size() > limit || value.size() > limit)
            throw std::runtime_error("Invalid delta state size");
        if (base.size() < block || value.size() < block)
            return {};
        std::unordered_map<std::uint64_t, Matches> index;
        index.reserve(base.size() / block);
        for (std::size_t offset = 0; offset + block <= base.size(); offset += block) {
            auto& entry = index[window(base.subspan(offset))];
            if (entry.count < candidates)
                entry.offsets[entry.count++] = static_cast<std::uint32_t>(offset);
        }
        std::vector<std::uint8_t> out;
        out.reserve(std::min(value.size(), std::size_t{65536}));
        number(out, static_cast<std::uint32_t>(value.size()));
        checksum(out, hash(base));
        checksum(out, hash(value));
        std::uint64_t power = 1;
        for (std::size_t i = 1; i < block; ++i)
            power *= multiplier;
        std::size_t cursor = 0, literal = 0;
        auto rolling = window(value);
        const auto flush = [&] {
            if (literal == cursor)
                return;
            number(out, static_cast<std::uint32_t>((cursor - literal) << 1));
            out.insert(out.end(), value.begin() + literal, value.begin() + cursor);
        };
        while (cursor + block <= value.size()) {
            std::size_t length = 0, offset = 0;
            // The same offset is especially useful for long repeated runs whose
            // hash bucket deliberately retains only a bounded set of candidates.
            const auto consider = [&](std::size_t at) {
                if (at + block > base.size() ||
                    !std::equal(value.begin() + cursor, value.begin() + cursor + block,
                                base.begin() + at))
                    return;
                std::size_t n = block;
                while (cursor + n < value.size() && at + n < base.size() &&
                       value[cursor + n] == base[at + n])
                    ++n;
                if (n > length) {
                    length = n;
                    offset = at;
                }
            };
            consider(cursor);
            if (const auto found = index.find(rolling); found != index.end())
                for (unsigned i = 0; i < found->second.count; ++i)
                    consider(found->second.offsets[i]);
            if (length >= block) {
                flush();
                number(out, static_cast<std::uint32_t>((length << 1) | 1));
                number(out, static_cast<std::uint32_t>(offset));
                cursor += length;
                literal = cursor;
                if (cursor + block <= value.size())
                    rolling = window(value.subspan(cursor));
            } else {
                if (cursor + block < value.size())
                    rolling =
                        (rolling - value[cursor] * power) * multiplier + value[cursor + block];
                ++cursor;
            }
            if (out.size() >= value.size())
                return {};
        }
        cursor = value.size();
        flush();
        if (out.size() >= value.size())
            return {};
        return out;
    }
    static std::vector<std::uint8_t> apply(std::span<const std::uint8_t> base,
                                           std::span<const std::uint8_t> patch) {
        if (base.empty() || base.size() > limit || patch.empty() || patch.size() > limit)
            throw std::runtime_error("Invalid delta state size");
        std::size_t cursor = 0;
        const auto byte = [&] {
            if (cursor == patch.size())
                throw std::runtime_error("Truncated delta state");
            return patch[cursor++];
        };
        const auto number = [&] {
            std::uint32_t value = 0;
            for (unsigned shift = 0; shift <= 28; shift += 7) {
                const auto part = byte();
                if (shift == 28 && (part & 0xf0))
                    throw std::runtime_error("Invalid delta integer");
                value |= static_cast<std::uint32_t>(part & 127) << shift;
                if (!(part & 128))
                    return value;
            }
            throw std::runtime_error("Invalid delta integer");
        };
        const auto checksum = [&] {
            std::uint64_t value = 0;
            for (unsigned shift = 0; shift < 64; shift += 8)
                value |= static_cast<std::uint64_t>(byte()) << shift;
            return value;
        };
        const auto size = number();
        if (!size || size > limit || checksum() != hash(base))
            throw std::runtime_error("Invalid delta baseline");
        const auto expected = checksum();
        std::vector<std::uint8_t> out;
        out.reserve(size);
        while (cursor < patch.size()) {
            const auto token = number(), length = token >> 1;
            if (!length || length > size - out.size())
                throw std::runtime_error("Invalid delta operation length");
            if (token & 1) {
                const auto offset = number();
                if (offset > base.size() || length > base.size() - offset)
                    throw std::runtime_error("Invalid delta copy range");
                out.insert(out.end(), base.begin() + offset, base.begin() + offset + length);
            } else {
                if (length > patch.size() - cursor)
                    throw std::runtime_error("Truncated delta literal");
                out.insert(out.end(), patch.begin() + cursor, patch.begin() + cursor + length);
                cursor += length;
            }
        }
        if (out.size() != size || hash(out) != expected)
            throw std::runtime_error("Delta state integrity mismatch");
        return out;
    }
};
} // namespace isaac::core

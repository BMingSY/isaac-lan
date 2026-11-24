#include "core/record_delta.h"
#include "core/state_codec.h"
#include <algorithm>
#include <array>
#include <map>
#include <unordered_map>

namespace isaac::core::record_delta {
namespace {
using Buffer = std::vector<std::uint8_t>;
using state_codec::Tag;
constexpr std::array<std::uint8_t, 4> signature{'I', 'R', 'F', 1};
constexpr unsigned maxRows = 4096, transposeAt = 8;
constexpr std::uint8_t zeroLane = 0, literalLane = 1, sparseLane = 2;

void require(bool valid) {
    if (!valid)
        throw std::runtime_error("Invalid keyed record frame");
}
struct Input {
    Bytes rest;
    Bytes take(std::size_t size) {
        require(size <= rest.size());
        const auto res = rest.first(size);
        rest = rest.subspan(size);
        return res;
    }
    std::uint64_t integer(unsigned width) {
        std::uint64_t result = 0;
        for (auto b : take(width))
            result = (result << 8) | b;
        return result;
    }
    unsigned number() {
        unsigned result = 0;
        for (unsigned shift = 0; shift <= 28; shift += 7) {
            const auto b = integer(1);
            require(shift < 28 || b <= 15);
            result |= static_cast<unsigned>(b & 127) << shift;
            if (!(b & 128))
                return result;
        }
        throw std::runtime_error("Invalid record integer");
    }
};
void number(Buffer& out, unsigned n) {
    while (n >= 128) {
        out.push_back(static_cast<std::uint8_t>(n | 128));
        n >>= 7;
    }
    out.push_back(static_cast<std::uint8_t>(n));
}
void append(Buffer& out, Bytes data) {
    out.insert(out.end(), data.begin(), data.end());
}
void skip(Input& in, state_codec::Budget& budget, unsigned depth) {
    budget.visit(depth);
    switch (static_cast<Tag>(in.integer(1))) {
    case Tag::falseValue:
    case Tag::trueValue:
        return;
    case Tag::float32:
    case Tag::int32:
        in.take(4);
        return;
    case Tag::int64:
        in.take(8);
        return;
    case Tag::string:
        in.take(in.integer(2));
        return;
    case Tag::array: {
        const auto count = in.integer(2);
        for (unsigned i = 0; i < count; ++i)
            skip(in, budget, depth + 1);
        return;
    }
    default:
        throw std::runtime_error("Invalid record field");
    }
}
std::uint64_t key(Input& in) {
    const auto tag = static_cast<Tag>(in.integer(1));
    require(tag == Tag::int32 || tag == Tag::int64);
    return in.integer(tag == Tag::int32 ? 4 : 8);
}
struct Family {
    std::uint64_t first, second;
    std::size_t width;
    auto operator<=>(const Family&) const = default;
};
struct Row {
    std::uint64_t id;
    Family family;
    Bytes header, bytes;
};
struct Frame {
    Bytes prefix;
    std::vector<Row> rows;
    std::unordered_map<std::uint64_t, unsigned> identities;
    std::map<Family, unsigned> templates;
    explicit Frame(Bytes data) {
        if (data.empty())
            return;
        require(framed(data) && data.size() <= state_codec::maxBytes);
        Input in{data.subspan(signature.size())};
        in.take(in.integer(4));
        require(in.integer(1) == static_cast<unsigned>(Tag::array));
        const auto count = in.integer(2);
        require(count && count <= maxRows);
        prefix = data.first(data.size() - in.rest.size());
        rows.reserve(count);
        state_codec::Budget budget;
        budget.visit(0);
        for (unsigned i = 0; i < count; ++i) {
            const auto start = in.rest;
            require(in.integer(1) == static_cast<unsigned>(Tag::array));
            const auto fields = in.integer(2);
            require(fields >= 5);
            budget.visit(1, 6);
            const auto id = key(in), first = key(in), second = key(in);
            require(identities.emplace(id, i).second);
            key(in);
            key(in);
            const auto header = start.first(start.size() - in.rest.size());
            const auto body = in.rest;
            for (unsigned j = 5; j < fields; ++j)
                skip(in, budget, 2);
            const auto bytes = body.first(body.size() - in.rest.size());
            const Family family{first, second, bytes.size()};
            rows.push_back({id, family, header, bytes});
            templates.try_emplace(family, i);
        }
        require(in.rest.empty());
    }
};
std::uint32_t checksum(Bytes bytes) {
    std::uint32_t value = 2166136261u;
    for (auto b : bytes)
        value = (value ^ b) * 16777619u;
    return value;
}
void encodeGroup(Buffer& out, const Frame& value, const Frame& base,
                 const std::vector<unsigned>& order) {
    const auto& first = value.rows[order.front()];
    const auto width = first.bytes.size(), count = order.size();
    number(out, count);
    number(out, width);
    auto proto = first.bytes;
    const auto found = base.templates.find(first.family);
    number(out, found == base.templates.end() ? 0 : found->second + 1);
    if (found == base.templates.end())
        append(out, proto);
    else
        proto = base.rows[found->second].bytes;
    Buffer changes(count * width);
    // Capture order tends to persist across ticks. Encode gaps within the family
    // and changes in its displacement from the acknowledged ordering.
    unsigned next = 0;
    int priorDisplacement = 0;
    for (unsigned i = 0; i < count; ++i) {
        const auto& row = value.rows[order[i]];
        number(out, order[i] - next);
        next = order[i] + 1;
        const auto match = base.identities.find(row.id);
        auto ref = proto;
        const bool retained =
            match != base.identities.end() && base.rows[match->second].family == row.family;
        bool sameHeader = false;
        if (retained) {
            const int displacement = static_cast<int>(match->second) - static_cast<int>(order[i]);
            const int delta = displacement - priorDisplacement;
            number(out, 1 + static_cast<unsigned>(delta < 0 ? -2 * delta - 1 : 2 * delta));
            priorDisplacement = displacement;
            const auto& prior = base.rows[match->second];
            ref = prior.bytes;
            sameHeader = std::ranges::equal(prior.header, row.header);
        } else {
            number(out, 0);
        }
        number(out, sameHeader ? 0 : row.header.size());
        if (!sameHeader)
            append(out, row.header);
        for (unsigned j = 0; j < width; ++j)
            changes[i * width + j] = static_cast<std::uint8_t>(row.bytes[j] - ref[j]);
    }
    if (count < transposeAt) {
        append(out, changes);
        return;
    }
    // Keep presence masks together. Repeated zero lanes then cost very little
    // after compression, including long shared asset names and numeric prefixes.
    const auto modes = out.size();
    out.resize(modes + width);
    Buffer lane(count), mask((count + 7) / 8);
    for (unsigned j = 0; j < width; ++j) {
        unsigned changed = 0;
        std::fill(mask.begin(), mask.end(), 0);
        for (unsigned i = 0; i < count; ++i) {
            lane[i] = changes[i * width + j];
            if (lane[i]) {
                mask[i / 8] |= static_cast<std::uint8_t>(1u << (i % 8));
                ++changed;
            }
        }
        if (!changed)
            continue;
        if (changed + mask.size() < count) {
            out[modes + j] = sparseLane;
            append(out, mask);
            for (auto b : lane)
                if (b)
                    out.push_back(b);
        } else {
            out[modes + j] = literalLane;
            append(out, lane);
        }
    }
}
Bytes reference(const Frame& base, unsigned index, unsigned width) {
    require(index && index <= base.rows.size());
    const auto bytes = base.rows[index - 1].bytes;
    require(bytes.size() == width);
    return bytes;
}
} // namespace

bool framed(Bytes value) {
    return value.size() >= signature.size() &&
           std::equal(signature.begin(), signature.end(), value.begin());
}
std::vector<std::uint8_t> encode(Bytes bytes, Bytes baseline) {
    require(framed(bytes));
    const Frame current(bytes), base(baseline);
    std::map<Family, std::vector<unsigned>> groups;
    for (unsigned i = 0; i < current.rows.size(); ++i)
        groups[current.rows[i].family].push_back(i);
    Buffer out;
    number(out, checksum(bytes));
    number(out, current.prefix.size());
    append(out, current.prefix);
    number(out, current.rows.size());
    for (const auto& [family, order] : groups) {
        encodeGroup(out, current, base, order);
        if (out.size() >= state_codec::maxBytes)
            return {};
    }
    return out;
}
std::vector<std::uint8_t> expand(Bytes patch, Bytes baseline, std::size_t expectedSize) {
    require(!patch.empty() && patch.size() <= state_codec::maxBytes && expectedSize &&
            expectedSize <= state_codec::maxBytes);
    const Frame base(baseline);
    Input in{patch};
    const auto expectedHash = in.number();
    const auto prefix = in.take(in.number());
    const unsigned count = in.number();
    require(framed(prefix) && prefix.size() < expectedSize && count && count <= maxRows);
    std::vector<Buffer> rows(count);
    std::size_t remaining = expectedSize - prefix.size();
    unsigned produced = 0;
    while (produced < count) {
        const unsigned group = in.number(), width = in.number(), prototype = in.number();
        require(group && group <= count - produced && width <= remaining / group);
        remaining -= group * width;
        const auto common = prototype ? reference(base, prototype, width) : in.take(width);
        std::vector<std::span<std::uint8_t>> batch;
        batch.reserve(group);
        unsigned next = 0;
        int displacement = 0;
        for (unsigned i = 0; i < group; ++i) {
            const auto gap = in.number(), link = in.number();
            require(gap < count - next);
            const unsigned at = next + gap;
            next = at + 1;
            require(rows[at].empty());
            unsigned match = 0;
            if (link) {
                const unsigned code = link - 1;
                require(code <= 4 * maxRows);
                displacement +=
                    (code & 1) ? -static_cast<int>(code / 2) - 1 : static_cast<int>(code / 2);
                const int index = static_cast<int>(at) + displacement;
                require(index >= 0 && static_cast<unsigned>(index) < base.rows.size());
                match = static_cast<unsigned>(index) + 1;
            }
            const auto ref = match ? reference(base, match, width) : common;
            const unsigned headerSize = in.number();
            require(headerSize || match);
            const auto header = headerSize ? in.take(headerSize) : base.rows[match - 1].header;
            require(header.size() <= remaining);
            remaining -= header.size();
            auto& row = rows[at];
            row.reserve(header.size() + width);
            append(row, header);
            append(row, ref);
            batch.push_back(std::span(row).last(width));
        }
        if (group < transposeAt) {
            for (auto row : batch) {
                const auto changes = in.take(width);
                for (unsigned j = 0; j < width; ++j)
                    row[j] += changes[j];
            }
        } else {
            const auto modes = in.take(width);
            for (unsigned j = 0; j < width; ++j) {
                if (modes[j] == zeroLane)
                    continue;
                require(modes[j] == literalLane || modes[j] == sparseLane);
                const auto mask = modes[j] == sparseLane ? in.take((group + 7) / 8) : Bytes{};
                for (unsigned i = 0; i < group; ++i)
                    if (mask.empty() || (mask[i / 8] & (1u << (i % 8))))
                        batch[i][j] += static_cast<std::uint8_t>(in.integer(1));
            }
        }
        produced += group;
    }
    require(!remaining && in.rest.empty());
    Buffer result;
    result.reserve(expectedSize);
    append(result, prefix);
    for (const auto& row : rows)
        append(result, row);
    require(checksum(result) == expectedHash);
    return result;
}
} // namespace isaac::core::record_delta

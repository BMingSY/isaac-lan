#include "core/record_delta.h"
#include "support/combat_records.h"
#include <algorithm>
#include <cstdio>
#include <stdexcept>
#include <string>

namespace {
namespace records = isaac::core::record_delta;
using isaac::tests::records::frame;
using Buffer = std::vector<std::uint8_t>;
void require(bool valid) {
    if (!valid)
        throw std::runtime_error("Record delta contract failed");
}
template <class F> void rejects(F action) {
    try {
        action();
    } catch (const std::runtime_error&) {
        return;
    }
    throw std::runtime_error("Invalid records accepted");
}
} // namespace
int main() {
    try {
        std::vector<int> ids(76);
        for (unsigned i = 0; i < ids.size(); ++i)
            ids[i] = i + 1;
        const auto original = frame(ids, 0);
        ids.erase(ids.begin() + 11, ids.begin() + 20);
        std::reverse(ids.begin(), ids.end());
        ids.insert(ids.begin() + 3, 1007);
        const auto middle = frame(ids, 3), latest = frame(ids, 8);
        for (const auto& base : {Buffer{}, original, middle, latest}) {
            const auto patch = records::encode(latest, base);
            require(records::expand(patch, base, latest.size()) == latest);
            rejects([&] { records::expand(patch, base, latest.size() - 1); });
            rejects([&] { records::expand(patch, base, isaac::state_codec::maxBytes + 1); });
            auto corrupt = patch;
            corrupt.front() ^= 1;
            rejects([&] { records::expand(corrupt, base, latest.size()); });
            for (auto length : {std::size_t{}, patch.size() / 2, patch.size() - 1})
                rejects([&] {
                    records::expand(records::Bytes(patch).first(length), base, latest.size());
                });
            corrupt = patch;
            corrupt.push_back(0);
            rejects([&] { records::expand(corrupt, base, latest.size()); });
        }
        const auto dependent = records::encode(latest, middle);
        rejects([&] { records::expand(dependent, original, latest.size()); });
        rejects([&] { records::expand(dependent, {}, latest.size()); });
        rejects([&] { records::encode(frame({30, 30}, 7), {}); });
        for (const auto& invalid : {Buffer{0}, Buffer{'I', 'R', 'F', 1}, frame({}, 0)})
            rejects([&] { records::encode(invalid, {}); });
        const auto small = frame({9}, 8);
        require(records::expand(records::encode(small, original), original, small.size()) == small);
        std::puts("PASS independent and acknowledged baselines, reorder, retirement, field widths "
                  "and malformed patches");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "%s\n", error.what());
        return 1;
    }
}

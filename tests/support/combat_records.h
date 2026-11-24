#pragma once
#include "core/state_codec.h"
#include <string>

namespace isaac::tests::records {
inline std::vector<std::uint8_t> frame(std::vector<int> ids, unsigned tick) {
    isaac::state_codec::Writer rows;
    rows.array(ids.size());
    for (const int id : ids) {
        rows.array(8);
        for (const std::int64_t field : std::array<std::int64_t, 5>{
                 id, id % 2, id == 4 ? tick : 0, 0, id % 3 ? id : (std::int64_t{1} << 40) + id})
            rows.number(field);
        rows.array(2);
        rows.number(static_cast<double>(id) + tick / 16.);
        rows.number(id % 3 == 0 ? -0.0 : 0.0);
        rows.boolean(id == 9 && tick != 0);
        rows.string(id == 7 && tick == 8 ? "changed shape" : std::string(48, 'x'));
    }
    std::vector<std::uint8_t> bytes{'I', 'R', 'F', 1, 0,
                                    0,   0,   2,   0, static_cast<std::uint8_t>(tick)};
    bytes.insert(bytes.end(), rows.data().begin(), rows.data().end());
    return bytes;
}
} // namespace isaac::tests::records
